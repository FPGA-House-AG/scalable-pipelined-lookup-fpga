package scalablePipelinedLookup

import spinal.core._

case class LookupTop() extends Component {
  }
  val io = new Bundle {
  }
}

object ScalablePipelinedLookupVerilog extends App {
  Config.spinal.generateVerilog(LookupTop())
}

object ScalablePipelinedLookupVhdl extends App {
  Config.spinal.generateVhdl(LookupTop())
}
