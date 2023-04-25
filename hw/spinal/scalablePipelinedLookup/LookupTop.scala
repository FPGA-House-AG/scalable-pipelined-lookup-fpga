package scalablePipelinedLookup

import spinal.core._
import spinal.lib._
import spinal.lib.bus.amba4.axilite._
import spinal.lib.bus.misc.SizeMapping
import spinal.lib.bus.regif._
import spinal.lib.bus.regif.AccessType._


/** Scalable Pipelined Lookup top-level module.
  *
  * As a base, the SystemVerilog implementation was used. It can be found in the
  * `hw/systemverilog` directory.
  *
  * @todo Wrap with AXI4-Lite interface.
  *
  * @param dualChannel Dual channel lookup.
  * @param config Lookup configuration.
  */
case class LookupTop(
    dualChannel: Boolean = true,
    config: LookupDataConfig = LookupDataConfig(),
    axiConfig: AxiLite4Config = AxiLite4Config(32, 32),
    axiMapping: SizeMapping = SizeMapping(0x0L, 32 Bytes)
) extends Component {

  /** Count of memory channels. */
  val channelCount = if (dualChannel) 2 else 1

  val io = new Bundle {

    /** AXI4 interface for update and status.
     *
     * TODO: Move to regular Axi4 once RegIf gains support for it.
     */
    val axi = slave(AxiLite4(axiConfig))

    /** Lookup request streams. */
    val lookup = Vec(slave(Flow(config.IpAddr())), channelCount)

    /** Result streams. */
    val result = Vec(master(Flow(LookupResult(config))), channelCount)
  }

  /** AXI4-Lite peripheral address space. */
  object AxiAddress extends Enumeration {
    val UDPATE_ADDR = 0x00
    val UPDATE_PREFIX = 0x04
    val UPDATE_PREFIX_INFO = 0x14
    val UPDATE_CHILD = 0x18
    val UPDATE_COMMAND = 0x20
    val UPDATE_STATUS = 0x24
  }

  /** Register interface. */
  val regs = new Area {
    val regif = BusInterface(io.axi, axiMapping)

    val updateAddr = regif.newRegAt(AxiAddress.UDPATE_ADDR, "Update interface address")
    val stageId =
      updateAddr.field(config.StageId(), WO, "Stage ID to insert the data to.")
    val location =
      updateAddr.fieldAt(16, config.Location(), WO, "Location in the memory of the selected stage.")

    val maxIpLength = 128
    val updatePrefix = Array.tabulate(maxIpLength / 32) { i =>
      regif
        .newRegAt(AxiAddress.UPDATE_PREFIX + i * 4, f"Lookup prefix (word ${i})")
        .field(Bits(32 bits), WO)
    }
    // For now only the first one is used, as only IPv4 is supported.

    val updatePrefixInfo = regif.newRegAt(AxiAddress.UPDATE_PREFIX_INFO, "Prefix information.")
    val prefixLen =
      updatePrefixInfo.field(config.BitPos(), WO, "Prefix length.")
    // Once IPv6 support is added there will be IP address variant.

    val updateChild = regif.newRegAt(AxiAddress.UPDATE_CHILD, "Child information.")
    val childStageId =
      updateChild.field(config.StageId(), WO, "Child stage ID.")
    val childLocation =
      updateChild.fieldAt(8, config.Location(), WO, "Child location.")
    val childHasRight =
      updateChild.fieldAt(24, Bool, WO, "Child has right child.")
    val childHasLeft =
      updateChild.fieldAt(25, Bool, WO, "Child has left child.")

    val updateCommand = regif.newRegAt(AxiAddress.UPDATE_COMMAND, "Command register to execute update command.")
    val updateRequest = RegInit(False)
    when(updateCommand.hitDoWrite) {
      updateRequest := True
    }

    val updateStatus = regif.newRegAt(AxiAddress.UPDATE_STATUS, "Memory update status.")
    val updatePending =
      updateStatus.field(Bool, AccessType.RO, 0, "Memory update has been pushed to execute.")
    updatePending.setAsReg().init(False)

    val updateData = Reg(LookupStageBundle(config))
    updateData.update init False
    when(updateRequest && !updatePending) {
      updatePending := True
      updateData.update := True
      updateData.ipAddr := updatePrefix(0)
      updateData.bitPos := prefixLen
      updateData.stageId := stageId
      updateData.location := location
      updateData.child.stageId := childStageId
      updateData.child.location := childLocation
      updateData.child.childLr.hasLeft := childHasLeft
      updateData.child.childLr.hasRight := childHasRight
    }
  }

  /** Lookup pipeline stages. */
  val stages = Array.tabulate(config.ipAddrWidth)(LookupStagesWithMem(_, channelCount, config))

  // First stage connection.
  for (((outside, inside), index) <- io.lookup zip stages(0).io.prev zipWithIndex) {
    when(outside.valid) {
      // Prioritise lookup request.
      inside.valid := True
      inside.update := False
      inside.ipAddr := outside.payload
      inside.bitPos := 0
      inside.stageId := 0
      inside.location := 0
      inside.child.assignFromBits(B(0, inside.child.asBits.getWidth bits))
    } otherwise {
      /* For now, update is possible on the first channel only, when no lookup is
       * performed. Thus, it is required to have an update acknowledge signal.
       */
      if (index == 0) {
        when(regs.updateRequest) {
          inside.valid := regs.updateRequest
          inside.payload := regs.updateData
          regs.updatePending := False
        } otherwise {
          inside.valid := False
          inside.payload.assignFromBits(B(0, inside.payload.asBits.getWidth bits))
        }
      } else {
        inside.valid := False
        inside.payload.assignFromBits(B(0, inside.payload.asBits.getWidth bits))
        // TODO: Use clearAll() once
        // https://github.com/SpinalHDL/SpinalHDL/pull/1078 is merged.
      }
    }
  }

  // Inter-stage connection.
  stages.sliding(2).foreach {
    case Array(prev, next) => (prev.io.next <> next.io.prev)
  }

  // Last stage connection.
  for ((outside, inside) <- io.result zip stages.last.io.next) {
    outside.valid := inside.valid && !inside.payload.update
    outside.ipAddr := inside.ipAddr
    outside.lookupResult := inside.child
  }
}

object LookupTopVerilog extends App {
  Config.spinal.generateVerilog(LookupTop()).printPruned()
}
