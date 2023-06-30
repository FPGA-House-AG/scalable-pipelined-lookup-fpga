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
    ipAddrWidth: Int = 32,
    locationWidth: Int = 11,
    resultWidth: Int = 10,
    memInitTemplate: Option[String] = Some("hw/gen/meminit/stage00.mem")
) {
  def IpAddr() = Bits(ipAddrWidth bits)
  def Location() = UInt(locationWidth bits)

  def bitPosWidth = log2Up(ipAddrWidth) + 1
  def BitPos() = UInt(bitPosWidth bits)

  def stageIdWidth = bitPosWidth
  def StageId() = UInt(stageIdWidth bits)

  def Result() = UInt(resultWidth bits)
}

/** Lookup stage configuration.
  *
  * @param dataConfig General data configuration.
  * @param stageId ID of the stage.
  */
case class StageConfig(dataConfig: LookupDataConfig, stageId: Int) {

  /** RAM data width. */
  def memDataWidth = LookupMemData(dataConfig).asBits.getBitsWidth

  printf("StageConfig() memDataWidth = %d bits\n", memDataWidth)

  /** RAM address width, depending on depth in the tree. Stage N has N address bits, even for N=0! */
  def memAddrWidth = if (stageId < dataConfig.locationWidth) stageId else dataConfig.locationWidth

  /** MemIf interface configuration. */
  def memIfConfig = MemIfConfig(memDataWidth, memAddrWidth)
}

/** Child select bundle. */
case class ChildSelBundle() extends Bundle() {

  /** Child has right leaf. */
  val hasRight = Bool()

  /** Child has left leaf. */
  val hasLeft = Bool()
}

/** Pointer to the left and right child, and which child(s) is/are present there */
case class LookupChildBundle(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  val stageId = config.StageId()
  val location = config.Location()
  val childLr = ChildSelBundle()
}

/** Lookup memory entry. */
case class LookupMemData(config: LookupDataConfig, padWidth: Int = 4) extends Bundle with PaddedMultiData {
  // IP address prefix at this tree node
  val prefix = config.IpAddr()
  val prefixLen = config.BitPos()
  // result if this is best prefix match
  val result = config.Result()
  // pointer to childs of this tree node
  val child = LookupChildBundle(config, padWidth)
}

/** Lookup stage main I/O bundle. */
case class LookupStageBundle(config: LookupDataConfig) extends Bundle {
  val update = Bool()
  // IP address during lookups, IP address prefix during updates
  val ipAddr = config.IpAddr()
  // bit position during lookups, prefix length during updates
  val bitPos = config.BitPos()
  // next lookup location during lookups, destination write location during updates
  val stageId = config.StageId()
  val location = config.Location()
  // used only during updates
  val child = LookupChildBundle(config)
  // best/last match result during lookups, result value during updates
  val result = config.Result()
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
    val mem = master(MemIf(config.memIfConfig))
  }

  if (writeChannel) {
    // Data written to lookup table when updating.
    val writeData = LookupMemData(config.dataConfig)
    writeData.setAsComb()
    writeData.prefix := io.prev.ipAddr
    writeData.prefixLen := io.prev.bitPos
    writeData.child := io.prev.child
    writeData.result := io.prev.result
    io.mem.wrdata := writeData.asBits

    // Write to stage memory if update is requested.
    io.mem.we := io.prev.valid && io.prev.update && (io.prev.stageId === config.stageId)
  } else {
    io.mem.wrdata.clearAll()
    io.mem.we := False
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
case class LookupResultStage(config: StageConfig, registerPreMux: Boolean) extends Component {
  val io = new Bundle {

    /** Interface to LookupMemStage. */
    val interstage = slave(LookupInterstageFlow(config.dataConfig))

    /** Interface to the next stage. */
    val next = master(LookupStageFlow(config.dataConfig))
  }

  val lookup    = io.interstage.lookup
  val memOutput = io.interstage.memOutput

  // does lookup.ipAddr match this nodes' prefix?
  val stageSel = lookup.stageId === config.stageId
  val prefixMask = (S"33'x100000000" |>> memOutput.prefixLen).resize(32).asBits
  val prefixXor = (lookup.ipAddr ^ memOutput.prefix)
  val prefixXorMasked = (prefixXor & prefixMask)
  //val prefixMatch = (prefixXorMasked === 0)

  // select right child node when bit at bitPos in ipAddr is 1, left child otherwise
  // note that bitPos 0 the most significant bit
  val mask =  B"32'x80000000" |>> lookup.bitPos
  val masked_ip_addr = lookup.ipAddr & mask
  val rightSel = masked_ip_addr.orR

  // if selected child is present
  val childLr = memOutput.child.childLr
  val hasChild = (
    (childLr.hasLeft && !rightSel) || (childLr.hasRight && rightSel)
  )

  // if a lookup in this stage is done
  val lookupActive = stageSel && !lookup.update

  val delay = if (registerPreMux) 1 else 0

  // IP address is passed through.
  io.next.ipAddr := Delay(lookup.ipAddr, delay)

  io.next.stageId := Mux(
    Delay(stageSel, delay) && !Delay(lookup.update, delay)/* && Delay(hasChild, delay)*/,
    Delay(memOutput.child.stageId, delay),
    Delay(lookup.stageId, delay)
  )

  io.next.location := Mux(
    Delay(stageSel, delay) && !Delay(lookup.update, delay),
    Delay(memOutput.child.location + U(rightSel), delay),
    Delay(lookup.location, delay)
  )

  io.next.result := Mux(
    Delay(stageSel, delay) && !Delay(lookup.update, delay) && (Delay(prefixXorMasked, delay) === 0),
    // pass (best) result from this stage if a valid prefix match
    Delay(memOutput.result, delay),
    // pass earlier result in all other cases (stage not addressed, no lookup, no match)
    Delay(lookup.result, delay)
  )

  io.next.child  := Delay(lookup.child, delay)

  //io.next.bitPos := Mux(Delay(lookupActive, delay), Delay(lookup.bitPos, delay) + 1, Delay(lookup.bitPos, delay))
  io.next.bitPos := Delay(Mux(lookupActive, lookup.bitPos + 1, lookup.bitPos), delay)

  io.next.update := Delay(lookup.update, delay)
  io.next.valid  := Delay(io.interstage.valid, delay)
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
    registerPreMux: Boolean,
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
  //mem.addAttribute(new AttributeString("RAM_STYLE", "ultra"))

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
    (LookupMemStage(config, i == 0), LookupResultStage(config, registerPreMux))
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
      memStage.io.mem.we,
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
