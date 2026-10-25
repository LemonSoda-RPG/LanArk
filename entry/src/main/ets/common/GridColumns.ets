/**
 * Columns that fit in `widthVp` at the library's minimum card width.
 *
 * `widthVp` must be the grid's own layout width, which is what `Area.width`
 * already reports and which the container's horizontal padding has already been
 * taken out of. Converting that number with `px2vp` shrank it by the screen
 * density — 641.68vp became 283.66vp on a 2.375-density phone — and the estimate
 * fell to a single column that the minimum then pinned at two, which is how the
 * random screen ended up showing two columns beside the library's three.
 */
export function gridColumnsForWidth(widthVp: number, minimumCardWidth: number,
  gap: number, minimum: number = 2, maximum: number = 6): number {
  const estimated: number = Math.floor((widthVp + gap) / (minimumCardWidth + gap));
  return Math.min(Math.max(estimated, minimum), maximum);
}
