package utils

import spinal.core._

/** MultiData with field alignment using a configurable padding.
  *
  * It can be used to align a Bundle to, e.g., nibbles or bytes by setting
  * `padWidth` to 4 or 8.
  *
  * For example for a field of bit width of 6, with `padWidth` set to 4, the
  * resulting Bits are 8 bits long (so 2-bit padding to fill up to the nibble).
  */
trait PaddedMultiData extends MultiData {
  val padWidth: Int

  /** Get bits width with padding. */
  private def paddedBitsWidth(bits: Data): Int = {
    if (bits.getBitsWidth == -1) {
      SpinalError("Can't use PaddedMultiData on 0-length Data.")
    }

    val modulo = bits.getBitsWidth % padWidth
    bits.getBitsWidth + (if (modulo == 0) 0 else padWidth - modulo)
  }

  override def asBits: Bits = {
    var ret: Bits = null
    for ((eName, e) <- elements) {
      val ePadded = e.asBits.resize(paddedBitsWidth(e))
      if (ret == null.asInstanceOf[Object]) ret = ePadded
      else ret = ret ## ePadded
    }
    if (ret.asInstanceOf[Object] == null) ret = Bits(0 bits)
    ret
  }

  override def assignFromBits(bits: Bits): Unit = {
    var offset = bits.getBitsWidth
    for ((_, e) <- elements) {
      val paddedWidth = paddedBitsWidth(e)
      val padding = paddedWidth - e.getBitsWidth
      e assignFromBits bits(offset - padding - 1 downto offset - paddedWidth)
      offset -= paddedWidth
    }
  }

  override def getBitsWidth: Int = {
    var accumulateWidth = 0
    for ((_, e) <- elements) accumulateWidth += paddedBitsWidth(e)
    accumulateWidth
  }
}
