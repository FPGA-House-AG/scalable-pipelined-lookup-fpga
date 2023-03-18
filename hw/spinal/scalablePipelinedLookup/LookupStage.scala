package scalablePipelinedLookup

import scala.io.Source

import spinal.core._
import spinal.lib._

import utils.PaddedMultiData

/** Lookup configuration.
  *
  * @todo Can be probably simplified by deriving some widths from other.
  *
  * @param ipAddrWidth Width of the IP address. For IPv4 it is 32 bits.
  * @param locationWidth Location width.
  * @param memInitTemplate Template of memory initialization file. The template
  *     should have "00" in a place where stage number is supposed to be placed.
  *     If None, the stage memory is not initialized. The file should be in
  *     format recognized by Verilog's `readmemh` (can have comments).
  */
case class LookupDataConfig(
    ipAddrWidth: BitCount = 32 bits,
    locationWidth: BitCount = 11 bits,
    memInitTemplate: Option[String] = Some("hw/gen/meminit/stage00.mem")
) {
  def bitPosWidth = (log2Up(ipAddrWidth.value) + 1) bits
  def stageIdWidth = bitPosWidth
}

/** Child select bundle. */
case class ChildSelBundle() extends Bundle() {

  /** Child has left leaf. */
  val hasLeft = Bool()

  /** Child has right leaf. */
  val hasRight = Bool()
}

/** Lookup child information. */
case class LookupChildBundle(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val stageId = UInt(config.stageIdWidth)
  val location = UInt(config.locationWidth)
  val childLr = ChildSelBundle()
}

/** Lookup memory entry. */
case class LookupMemData(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val prefix = Bits(config.ipAddrWidth)
  val prefixLen = UInt(config.bitPosWidth)
  val child = LookupChildBundle(config)
}

/** Lookup stage main I/O bundle. */
case class LookupStageBundle(config: LookupDataConfig) extends Bundle {
  val update = Bool()
  val ipAddr = Bits(config.ipAddrWidth)
  val bitPos = UInt(config.bitPosWidth)
  val stageId = UInt(config.stageIdWidth)
  val location = UInt(config.locationWidth)
  val child = LookupChildBundle(config)
}

/** Lookup stage flow bundle. */
object LookupStageFlow {
  def apply(config: LookupDataConfig) = Flow(LookupStageBundle(config))
}

/** Lookup memory interface. */
case class LookupMemBundle(config: LookupDataConfig) extends Bundle with IMasterSlave {
  val writeEnable = Bool()
  val addr = UInt(config.locationWidth)
  val dataWrite = LookupMemData(config)
  val dataRead = LookupMemData(config)

  override def asMaster(): Unit = {
    out(writeEnable, addr, dataWrite)
    in(dataRead)
  }
}

/** Lookup pipeline stage.
  *
  * @param stageId Stage index.
  * @param config Stage configuration.
  * @param registerOutput Add a register stage for the output.
  */
case class LookupStage(stageId: Int, config: LookupDataConfig, registerOutput: Boolean = true) extends Component {
  val io = new Bundle {

    /** Interface to the previous stage. */
    val prev = slave(LookupStageFlow(config))

    /** Interface to the next stage. */
    val next = master(LookupStageFlow(config))

    /** Interface to memory port. */
    val mem = master(LookupMemBundle(config))
  }

  // Data written to lookup table when updating.
  io.mem.dataWrite.prefix := io.prev.ipAddr
  io.mem.dataWrite.prefixLen := io.prev.bitPos
  io.mem.dataWrite.child := io.prev.child

  // Write to stage memory if update is requested.
  io.mem.writeEnable := io.prev.valid && io.prev.update && (io.prev.stageId === stageId)
  io.mem.addr := io.prev.location

  val delayed = Delay(io.prev, 1)

  val stageSel = delayed.stageId === stageId
  val prefixMatch =
    ((delayed.ipAddr ^ io.mem.dataRead.prefix) >> (U(config.ipAddrWidth.value) - io.mem.dataRead.prefixLen)) === 0
  val validMatch = prefixMatch && stageSel

  // Right node is selected when bit at bitPos in ipAddr is 1.
  val rightSel = delayed.ipAddr(config.ipAddrWidth.value - 1 - delayed.bitPos.resize(delayed.bitPos.getBitsWidth - 1))

  // IP address is passed through.
  io.next.ipAddr := delayed.ipAddr

  val childLr = io.mem.dataRead.child.childLr
  val hasChild = (childLr.hasLeft && !rightSel) || (childLr.hasRight && rightSel)

  io.next.stageId := Mux(
    stageSel && !delayed.update && hasChild,
    io.mem.dataRead.child.stageId,
    delayed.stageId
  )

  io.next.location := Mux(
    stageSel && !delayed.update,
    io.mem.dataRead.child.location + Mux(rightSel, 1, 0),
    delayed.location
  )

  when(validMatch && !delayed.update) {
    io.next.child.stageId := stageId
    io.next.child.location := delayed.location
    io.next.child.childLr.hasLeft := False
    io.next.child.childLr.hasRight := False
  } otherwise {
    io.next.child := delayed.child
  }

  io.next.bitPos := Mux(
    stageSel && !delayed.update,
    delayed.bitPos + 1,
    delayed.bitPos
  )

  io.next.update := delayed.update
  io.next.valid := delayed.valid

  if (registerOutput) {
    io.next.setAsReg()
  }
}

/** Lookup pipeline stage with block RAM memory.
  *
  * @param stageId Stage index.
  * @param channelCount Count of channels.
  * @param config Lookup configuration.
  */
case class LookupStageMem(stageId: Int, channelCount: Int, config: LookupDataConfig) extends Component {
  val io = new Bundle {
    val prev = Vec(slave(LookupStageFlow(config)), channelCount)
    val next = Vec(master(LookupStageFlow(config)), channelCount)
  }

  /** Dual-port Block RAM memory. */
  val mem = Mem(LookupMemData(config).asBits, 1 << config.locationWidth.value)
  if (config.memInitTemplate != None) {
    mem.init(
      Source
        .fromFile(config.memInitTemplate.get.replace("00", f"$stageId%02d"))
        .getLines()
        .map(s => B("x" + s.replaceAll("//.*", "").trim))
        .toSeq
    )
  }
  mem.setTechnology(ramBlock)

  /** Lookup stage memory channels. */
  val channels = Array.fill(channelCount)(LookupStage(stageId, config))
  for ((channel, prev, next) <- channels lazyZip io.prev lazyZip io.next) {
    // Connect memory interface.
    channel.io.mem.dataRead assignFromBits mem.readWriteSync(
      channel.io.mem.addr,
      channel.io.mem.dataWrite.asBits,
      True,
      channel.io.mem.writeEnable
    )

    // Connect lookup interfaces.
    prev >> channel.io.prev
    channel.io.next >> next
  }
}
