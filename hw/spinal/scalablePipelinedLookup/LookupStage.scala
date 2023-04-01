package scalablePipelinedLookup

import scala.io.Source

import spinal.core._
import spinal.lib._
import spinal.lib.bus.bram._

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
    ipAddrWidth: Int = 32,
    locationWidth: Int = 11,
    memInitTemplate: Option[String] = Some("hw/gen/meminit/stage00.mem")
) {
  def bitPosWidth = log2Up(ipAddrWidth) + 1
  def stageIdWidth = bitPosWidth

  def memDataWidth = LookupMemData(this).asBits.getBitsWidth
  def bramConfig = BRAMConfig(memDataWidth, locationWidth)
}

/** Child select bundle. */
case class ChildSelBundle() extends Bundle() {

  /** Child has right leaf. */
  val hasRight = Bool()

  /** Child has left leaf. */
  val hasLeft = Bool()
}

/** Lookup child information. */
case class LookupChildBundle(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val stageId = UInt(config.stageIdWidth bits)
  val location = UInt(config.locationWidth bits)
  val childLr = ChildSelBundle()
}

/** Lookup memory entry. */
case class LookupMemData(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val prefix = Bits(config.ipAddrWidth bits)
  val prefixLen = UInt(config.bitPosWidth bits)
  val child = LookupChildBundle(config)
}

/** Lookup stage main I/O bundle. */
case class LookupStageBundle(config: LookupDataConfig) extends Bundle {
  val update = Bool()
  val ipAddr = Bits(config.ipAddrWidth bits)
  val bitPos = UInt(config.bitPosWidth bits)
  val stageId = UInt(config.stageIdWidth bits)
  val location = UInt(config.locationWidth bits)
  val child = LookupChildBundle(config)
}

/** Lookup stage flow bundle. */
object LookupStageFlow {
  def apply(config: LookupDataConfig) = Flow(LookupStageBundle(config))
}

/** Flow between LookupMem and LookupResult. */
object LookupInterstageFlow {
  def apply(config: LookupDataConfig) = Flow(new Bundle {
    val lookup = LookupStageBundle(config)
    val memOutput = LookupMemData(config)
  })
}

/** Memory lookup pipeline stage.
  *
  * @param stageId Stage index.
  * @param config Stage configuration.
  * @param writeChannel Enable memory write channel.
  */
case class LookupMemStage(
    stageId: Int,
    config: LookupDataConfig,
    writeChannel: Boolean
) extends Component {
  val io = new Bundle {

    /** Interface to the previous stage. */
    val prev = slave(LookupStageFlow(config))

    /** Interface to LookupResultStage. */
    val interstage = master(LookupInterstageFlow(config))

    /** Interface to memory port. */
    val mem = master(BRAM(config.bramConfig))
  }

  if (writeChannel) {
    // Data written to lookup table when updating.
    val writeData = LookupMemData(config)
    writeData.setAsComb()
    writeData.prefix := io.prev.ipAddr
    writeData.prefixLen := io.prev.bitPos
    writeData.child := io.prev.child
    io.mem.wrdata := writeData.asBits

    // Write to stage memory if update is requested.
    io.mem.we.setAllTo(
      io.prev.valid && io.prev.update && (io.prev.stageId === stageId)
    )
  }

  io.mem.en := True
  io.mem.addr := io.prev.location
  // TODO: Print information in simulation.

  val lookupDelayed = io.prev.m2sPipe
  io.interstage.valid := lookupDelayed.valid
  io.interstage.lookup := lookupDelayed.payload
  io.interstage.memOutput assignFromBits io.mem.rddata
}

/** Result lookup pipeline stage.
  *
  * @param stageId Stage index.
  * @param config Stage configuration.
  */
case class LookupResultStage(
    stageId: Int,
    config: LookupDataConfig
) extends Component {
  val io = new Bundle {

    /** Interface to LookupMemStage. */
    val interstage = slave(LookupInterstageFlow(config))

    /** Interface to the next stage. */
    val next = master(LookupStageFlow(config))
  }

  val lookup = io.interstage.lookup
  val memOutput = io.interstage.memOutput

  val stageSel = lookup.stageId === stageId
  val prefixShift = config.ipAddrWidth - memOutput.prefixLen
  val prefixMatch = ((lookup.ipAddr ^ memOutput.prefix) >> prefixShift) === 0

  // Right node is selected when bit at bitPos in ipAddr is 1.
  val rightSelBit = config.ipAddrWidth - 1 - lookup.bitPos.resize(config.bitPosWidth - 1)
  val rightSel = lookup.ipAddr(rightSelBit)

  // IP address is passed through.
  io.next.ipAddr := lookup.ipAddr

  val childLr = memOutput.child.childLr
  val hasChild = (
    (childLr.hasLeft && !rightSel) || (childLr.hasRight && rightSel)
  )

  val lookupActive = lookup.stageId === stageId && !lookup.update

  io.next.stageId := Mux(
    lookupActive && hasChild,
    memOutput.child.stageId,
    lookup.stageId
  )

  io.next.location := Mux(
    lookupActive,
    memOutput.child.location + Mux(rightSel, 1, 0),
    lookup.location
  )

  when(lookupActive && prefixMatch) {
    io.next.child.stageId := stageId
    io.next.child.location := lookup.location
    io.next.child.childLr.hasLeft := False
    io.next.child.childLr.hasRight := False
  } otherwise {
    io.next.child := lookup.child
  }

  io.next.bitPos := Mux(lookupActive, lookup.bitPos + 1, lookup.bitPos)

  io.next.update := lookup.update
  io.next.valid := io.interstage.valid
}

/** Lookup pipeline stage with block RAM memory.
  *
  * @param stageId Stage index.
  * @param channelCount Count of channels.
  * @param config Lookup configuration.
  * @param registerOutput Add a register stage for the `io.next` Flow.
  */
case class LookupStagesWithMem(
    stageId: Int,
    channelCount: Int,
    config: LookupDataConfig,
    registerOutput: Boolean = true
) extends Component {
  val io = new Bundle {

    /** Interface to the previous stage. */
    val prev = Vec(slave(LookupStageFlow(config)), channelCount)

    /** Interface to the next stage. */
    val next = Vec(master(LookupStageFlow(config)), channelCount)
  }

  /** Dual-port Block RAM memory. */
  val mem = Mem(LookupMemData(config).asBits, 1 << config.locationWidth)
  if (config.memInitTemplate != None) {
    mem.init(
      Source
        .fromFile(config.memInitTemplate.get.replace("00", f"$stageId%02d"))
        .getLines()
        .map(s => B("x" + s.replaceAll("//.*", "").trim))
        .toSeq
    )
  }

  /** Lookup stage memory channels.
    *
    * Enable write channel only for the first channel.
    */
  val channels = Array.tabulate(channelCount) { i =>
    (LookupMemStage(stageId, config, i == 0), LookupResultStage(stageId, config))
  }

  for (
    ((memStage, resultStage), prev, next) <-
      channels lazyZip io.prev lazyZip io.next
  ) {
    // Connect memory interface.
    if (memStage.writeChannel) {
      memStage.io.mem.rddata := mem.readWriteSync(
        memStage.io.mem.addr,
        memStage.io.mem.wrdata,
        memStage.io.mem.en,
        memStage.io.mem.we.andR
      )
    } else {
      memStage.io.mem.rddata := mem.readSync(memStage.io.mem.addr, memStage.io.mem.en)
    }

    // Connect lookup interfaces.
    prev >> memStage.io.prev
    memStage.io.interstage >> resultStage.io.interstage
    if (registerOutput) {
      resultStage.io.next >-> next
    } else {
      resultStage.io.next >> next
    }
  }
}
