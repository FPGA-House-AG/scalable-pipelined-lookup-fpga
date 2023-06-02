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
  def IpAddr() = Bits(ipAddrWidth bits)
  def Location() = UInt(locationWidth bits)

  def bitPosWidth = log2Up(ipAddrWidth) + 1
  def BitPos() = UInt(bitPosWidth bits)

  def stageIdWidth = bitPosWidth
  def StageId() = UInt(stageIdWidth bits)

}

/** Lookup stage configuration.
  *
  * @param dataConfig General data configuration.
  * @param stageId ID of the stage.
  */
case class StageConfig(dataConfig: LookupDataConfig, stageId: Int) {

  /** RAM data width. */
  def memDataWidth = LookupMemData(dataConfig).asBits.getBitsWidth

  /** RAM address width. */
  def memAddrWidth = {
    if (dataConfig.memInitTemplate != None) {
      dataConfig.locationWidth
    } else if ((stageId + 1) < dataConfig.locationWidth) {
      stageId + 1
    } else {
      dataConfig.locationWidth
    }
  }

  /** BRAM interface configuration. */
  def bramConfig = BRAMConfig(memDataWidth, memAddrWidth)
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
  val stageId = config.StageId()
  val location = config.Location()
  val childLr = ChildSelBundle()
}

/** Lookup memory entry. */
case class LookupMemData(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val prefix = config.IpAddr()
  val prefixLen = config.BitPos()
  val child = LookupChildBundle(config)
}

/** Lookup stage main I/O bundle. */
case class LookupStageBundle(config: LookupDataConfig) extends Bundle {
  val update = Bool()
  val ipAddr = config.IpAddr()
  val bitPos = config.BitPos()
  val stageId = config.StageId()
  val location = config.Location()
  val child = LookupChildBundle(config)

  // TODO: Split to lookup and update Flows.
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
  * @param config Stage configuration.
  * @param writeChannel Enable memory write channel.
  */
case class LookupMemStage(
    config: StageConfig,
    writeChannel: Boolean
) extends Component {
  val io = new Bundle {

    /** Interface to the previous stage. */
    val prev = slave(LookupStageFlow(config.dataConfig))

    /** Interface to LookupResultStage. */
    val interstage = master(LookupInterstageFlow(config.dataConfig))

    /** Interface to memory port. */
    val mem = master(BRAM(config.bramConfig))
  }

  if (writeChannel) {
    // Data written to lookup table when updating.
    val writeData = LookupMemData(config.dataConfig)
    writeData.setAsComb()
    writeData.prefix := io.prev.ipAddr
    writeData.prefixLen := io.prev.bitPos
    writeData.child := io.prev.child
    io.mem.wrdata := writeData.asBits

    // Write to stage memory if update is requested.
    io.mem.we.setAllTo(
      io.prev.valid && io.prev.update && (io.prev.stageId === config.stageId)
    )
  } else {
    io.mem.wrdata.clearAll()
    io.mem.we.clearAll()
  }

  io.mem.en := True
  // Previous stage location is resized due to the RAM size optimization.
  io.mem.addr := io.prev.location.resized
  // TODO: Print information in simulation.

  val lookupDelayed = io.prev.m2sPipe
  io.interstage.valid := lookupDelayed.valid
  io.interstage.lookup := lookupDelayed.payload
  io.interstage.memOutput assignFromBits io.mem.rddata
}

/** Result lookup pipeline stage.
  *
  * @param config Stage configuration.
  */
case class LookupResultStage(config: StageConfig) extends Component {
  val io = new Bundle {

    /** Interface to LookupMemStage. */
    val interstage = slave(LookupInterstageFlow(config.dataConfig))

    /** Interface to the next stage. */
    val next = master(LookupStageFlow(config.dataConfig))
  }

  val lookup = io.interstage.lookup
  val memOutput = io.interstage.memOutput

  val stageSel = lookup.stageId === config.stageId
  val prefixShift = config.dataConfig.ipAddrWidth - memOutput.prefixLen
  val prefixMatch = ((lookup.ipAddr ^ memOutput.prefix) >> prefixShift) === 0

  // Right node is selected when bit at bitPos in ipAddr is 1, starting from most significant bit
  val rightSelBit = config.dataConfig.ipAddrWidth - 1 - lookup.bitPos.resize(config.dataConfig.bitPosWidth - 1)
  val rightSel = lookup.ipAddr(rightSelBit)

  // IP address is passed through.
  io.next.ipAddr := lookup.ipAddr

  val childLr = memOutput.child.childLr
  val hasChild = (
    (childLr.hasLeft && !rightSel) || (childLr.hasRight && rightSel)
  )

  val lookupActive = lookup.stageId === config.stageId && !lookup.update

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
    io.next.child.stageId := config.stageId
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
  * @param config Lookup stage configuration.
  * @param channelCount Count of channels.
  * @param registerInterstage Add a register stage between memory fetch and data
  *                           processing stages.
  * @param registerOutput Add a register stage for the `io.next` Flow.
  */
case class LookupStagesWithMem(
    config: StageConfig,
    channelCount: Int,
    registerInterstage: Boolean,
    registerOutput: Boolean
) extends Component {
  val io = new Bundle {

    /** Interface to the previous stage. */
    val prev = Vec(slave(LookupStageFlow(config.dataConfig)), channelCount)

    /** Interface to the next stage. */
    val next = Vec(master(LookupStageFlow(config.dataConfig)), channelCount)
  }

  /** Dual-port Block RAM memory. */
  val mem = Mem(LookupMemData(config.dataConfig).asBits, 1 << config.memAddrWidth)

  if (config.dataConfig.memInitTemplate != None) {
    mem.init(
      Source
        .fromFile(config.dataConfig.memInitTemplate.get.replace("00", f"${config.stageId}%02d"))
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
    (LookupMemStage(config, i == 0), LookupResultStage(config))
  }

  for (
    (((memStage, resultStage), prev), next) <-
      channels zip io.prev zip io.next
  ) {
    // Connect memory interface.
    memStage.io.mem.rddata := mem.readWriteSync(
      memStage.io.mem.addr,
      memStage.io.mem.wrdata,
      memStage.io.mem.en,
      memStage.io.mem.we.andR,
      duringWrite = dontRead
    )

    // Connect lookup interfaces with optional register stages.
    prev >> memStage.io.prev
    if (registerInterstage) {
      memStage.io.interstage >-> resultStage.io.interstage
    } else {
      memStage.io.interstage >> resultStage.io.interstage
    }

    if (registerOutput) {
      resultStage.io.next >-> next
    } else {
      resultStage.io.next >> next
    }
  }
}
