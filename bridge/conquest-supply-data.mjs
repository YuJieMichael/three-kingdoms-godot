export const CONQUEST_BUNDLES = Object.freeze({supply_choice: '百工调拨令', supply_rations: '行军粮秣包',
  supply_recovery: '返城整备包', supply_siege: '攻城筹备包'});
export const conquestGems = (kind, level) => kind === 'city' ? 20 + level * 5 : 3 + level * 2;

/** Provenance for earned bundles lives in the independently validated conquest ledger. */
export function earnedConquestBundles(state, id) {
  return Object.values(state.conquestSupply?.records || {}).filter(row => row?.status === 'rewarded' &&
    row.drop?.kind === 'bundle' && row.drop.id === id).length;
}
