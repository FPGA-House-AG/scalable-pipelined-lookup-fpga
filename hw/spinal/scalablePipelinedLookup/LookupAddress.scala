package scalablePipelinedLookup

import spinal.core._
import spinal.lib._
import spinal.lib.bus.misc._
import spinal.lib.bus.amba4.axi._

// Note this is an experimental fork of LookupTop, for the purpose of BusSlaveFactory
// May get deleted later, undecided yet.

// companion object for case class
object LookupAddress {
  // generate VHDL and Verilog
  def main(args: Array[String]): Unit = {
    val vhdlReport = Config.spinal.generateVhdl({
      val toplevel = new LookupAddress()
      // return this
      toplevel
    })
    val verilogReport = Config.spinal.generateVerilog(LookupAddress())
    // verilogReport.printPruned()
  }
}

/** Scalable Pipelined Lookup top-level module. (fork of LookupTop)
  *
  * As a base, the SystemVerilog implementation was used. It can be found in the
  * `hw/systemverilog` directory.
  *
  * @todo Wrap with BusSlaveFactory driveFrom(), and implement an Axi4 derivative.
  *
  * @param dualChannel Dual channel lookup.
  * @param config Lookup configuration.
  */
case class LookupAddress(
    dualChannel: Boolean = true,
    config: LookupDataConfig = LookupDataConfig()
) extends Component {

  /** Count of memory channels. */
  val channelCount = if (dualChannel) 2 else 1

  val io = new Bundle {

    /** Lookup request streams. */
    val lookup = Vec(slave(Flow(config.IpAddr())), channelCount)

    /** Result streams. */
    val result = Vec(master(Flow(LookupResult(config))), channelCount)
  }

  val regs = new Area {
    val updateData = Reg(LookupStageBundle(config))
    val updatePending = RegInit(False)
    val updateRequest = RegInit(False)
    updateData.update init False
  }

  /** Lookup pipeline stages. */
  val stages = Array.tabulate(config.ipAddrWidth) { stageId =>
    LookupStagesWithMem(StageConfig(config, stageId), channelCount, false, true)
  }

  // First stage connection.
  for (((outside, inside), index) <- io.lookup zip stages(0).io.prev zipWithIndex) {
    inside.valid := outside.valid
    // this is optionally overwritten by later assignment
    inside.update := False
    inside.ipAddr := outside.payload
    inside.bitPos := 0
    inside.stageId := 0
    inside.location := 0
    inside.result := 0
    inside.child.assignFromBits(B(0, inside.child.asBits.getWidth bits))
  }

  // Inter-stage connection.
  stages.sliding(2).foreach {
    case Array(prev, next) => (prev.io.next <> next.io.prev)
  }

  // Last stage connection.
  for ((outside, inside) <- io.result zip stages.last.io.next) {
    outside.valid := inside.valid && !inside.payload.update
    outside.ipAddr := inside.ipAddr
    outside.lookupResult := inside.result
  }

  // address decoding assumes slave-local addresses
  def driveFrom(busCtrl: BusSlaveFactory) = new Area {
    assert(busCtrl.busDataWidth == 32)
    val size_mapping = SizeMapping(0, 4 kB)

    // pulse update only when lookup interface is idle
    val bus_slave_update_pulse = False
    busCtrl.onWritePrimitive(address = size_mapping, haltSensitive = false, documentation = null) {
      // lookup on first port is idle?
      when(io.lookup.apply(0).valid === False) {
        bus_slave_update_pulse := True
        // lookup is busy, pause the write
      } otherwise {
        busCtrl.writeHalt()
      }
    }
    stages(0).io.prev.apply(0).update := bus_slave_update_pulse
  }
}
