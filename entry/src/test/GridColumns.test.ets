import { describe, expect, it } from '@ohos/hypium';
import { gridColumnsForWidth } from '../main/ets/common/GridColumns';

/**
 * The random screen used to report two columns on a phone whose library showed
 * three, because the width it measured had been converted to vp twice.
 */
export default function gridColumnsTest() {
  describe('gridColumns', () => {
    it('gives the library three columns at its measured width', 0, () => {
      // What the library grid measures on this device: 641.68vp.
      expect(gridColumnsForWidth(641.68, 160, 10)).assertEqual(3);
    });

    it('gives four columns only when the width really allows four', 0, () => {
      // The same width measured with the padding still inside it.
      expect(gridColumnsForWidth(673.68, 160, 10)).assertEqual(4);
      expect(gridColumnsForWidth(669, 160, 10)).assertEqual(3);
      expect(gridColumnsForWidth(670, 160, 10)).assertEqual(4);
    });

    // The bug: 641.68vp converted with px2vp became 283.66vp, the estimate fell
    // to a single column, and the minimum pinned the grid at two.
    it('never falls below two columns, however narrow the measurement', 0, () => {
      expect(gridColumnsForWidth(283.66, 160, 10)).assertEqual(2);
      expect(gridColumnsForWidth(0, 160, 10)).assertEqual(2);
    });

    it('never grows past six columns', 0, () => {
      expect(gridColumnsForWidth(1600, 160, 10)).assertEqual(6);
    });
  });
}
