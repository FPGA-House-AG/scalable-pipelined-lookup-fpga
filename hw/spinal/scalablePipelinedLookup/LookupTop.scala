package scalablePipelinedLookup

import spinal.core._
import spinal.lib._

/** Bundle representing a lookup result. */
case class LookupResult(config: LookupDataConfig) extends Bundle {

  /** IP address associated with the result. */
  val ipAddr = Bits(config.ipAddrWidth bits)

  /** Last pipeline stage output. */
  val lookupResult = LookupChildBundle(config)
}

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
case class LookupTop(dualChannel: Boolean = true, config: LookupDataConfig = LookupDataConfig()) extends Component {

  /** Count of memory channels. */
  val channelCount = if (dualChannel) 2 else 1

  val io = new Bundle {

    /** Update input vector. */
    val update = in(LookupStageBundle(config))

    /** Update acknowledge signel.
      *
      * Update vector should be valid until acknowledge is asserted.
      */
    val updateAck = out Bool ()

    /** Lookup request streams. */
    val lookup = Vec(slave(Stream(Bits(config.ipAddrWidth bits))), channelCount)

    /** Result streams. */
    val result = Vec(master(Stream(LookupResult(config))), channelCount)
  }
  io.updateAck.setAsReg()

  /** Lookup pipeline stages. */
  val stages = Array.tabulate(config.ipAddrWidth.value)(LookupStageMem(_, channelCount, config))

  // First stage connection.
  for (((outside, inside), index) <- io.lookup zip stages(0).io.prev zipWithIndex) {
    // For now we don't support back-pressure.
    outside.ready := True

    /* For now, update is possible on the first channel only, when no lookup is
     * performed. Thus, it is required to have an update acknowledge signal.
     */
    if (index == 0) {
      io.updateAck := False
    }

    when(outside.valid) {
      // Lookup request.
      inside.valid := True
      inside.update := False
      inside.ipAddr := outside.payload
      inside.bitPos := 0
      inside.stageId := 0
      inside.location := 0
      inside.child.assignDontCare()
    } otherwise {
      // Add update capability for the first port.
      if (index == 0) {
        inside.valid := io.update.update
        inside.payload := io.update
        io.updateAck := True
      } else {
        inside.valid := False
        inside.payload.assignDontCare()
      }
    }
  }

  // Inter-stage connection.
  stages.sliding(2).foreach {
    case Array(prev, next) => (prev.io.next <> next.io.prev)
  }

  // Last stage connection.
  for ((outside, inside) <- io.result zip stages.last.io.next) {
    outside.valid := inside.valid
    outside.ipAddr := inside.ipAddr
    outside.lookupResult := inside.child
  }
}

object LookupTopVerilog extends App {
  Config.spinal.generateVerilog(LookupTop()).printPruned()
}
