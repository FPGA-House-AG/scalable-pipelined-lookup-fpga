package scalablePipelinedLookup

import spinal.core._
import spinal.lib._

case class MemIfConfig(dataWidth: Int, addressWidth: Int)

case class MemIf(config: MemIfConfig) extends Bundle with IMasterSlave {
  val en     = Bool()
  val we     = Bool()
  val addr   = UInt(config.addressWidth bits)
  val wrdata = Bits(config.dataWidth bits)
  val rddata = Bits(config.dataWidth bits)

  /** Set the direction of the bus when it is used as master */
  override def asMaster(): Unit = {
    out(en, we, addr, wrdata)
    in(rddata)
  }

  /**
    * Connect two MemIf bus together Master >> Slave
    */
  def >> (sink: MemIf): Unit = {
    assert(this.config.addressWidth >= sink.config.addressWidth, "MemIf mismatch width address (slave address is bigger than master address )")
    assert(this.config.dataWidth == sink.config.dataWidth, "MemIf mismatch width data (slave and master doesn't have the same data width)")

    this.rddata := sink.rddata

    sink.addr   := this.addr.resized
    sink.we     := this.we
    sink.wrdata := this.wrdata
    sink.en     := this.en
  }

  /** Slave << Master */
  def << (sink: MemIf): Unit = sink >> this
}
