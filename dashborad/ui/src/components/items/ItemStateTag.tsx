/**
 * The item state badge.
 *
 * THREE states, not one boolean, and the distinction is the whole point of this
 * component. Migration 121 states it directly:
 *
 *   "is_available is a merchant-controlled toggle; deleted_at is an
 *    administrative removal. Conflating them means 'deleting' an item does not
 *    remove it from search."
 *
 *   available    deleted_at IS NULL, is_available = true    in the menu, orderable
 *   unavailable  deleted_at IS NULL, is_available = false   sold out — merchant's doing
 *   deleted      deleted_at IS NOT NULL                    retired — admin's doing
 *
 * Rendering those as one "Active / Inactive" pair would be actively misleading:
 * an operator seeing "Inactive" could not tell a sold-out burger (recoverable,
 * the merchant will restock) from a delisted illegal item (recoverable, but for a
 * different reason), and would not know which one to reverse.
 *
 * The tooltip on each state says the same thing in words, because "Unavailable"
 * and "Deleted" are labels an operator has to learn, and a wrong guess between
 * them leads to the wrong action.
 */
import { Tag, Tooltip } from 'antd';
import { CheckCircleOutlined, DeleteOutlined, StopOutlined } from '@ant-design/icons';
import { itemState, type Item, type ItemState } from '../../constants';
import { useLang } from '../../i18n/LangProvider';
import type { StringKey } from '../../i18n/strings';
import { t } from '../../i18n/strings';

/**
 * Tag presets, per entity, in one place — the same rule STATUS_TAG_COLOR
 * follows in theme/tokens.ts. Tag's API takes presets rather than tokens, so the
 * mapping is explicit rather than derived.
 */
const STATE_TAG: Record<ItemState, { color: string; icon: React.ReactNode }> = {
  live: { color: 'green', icon: <CheckCircleOutlined /> },
  unavailable: { color: 'orange', icon: <StopOutlined /> },
  deleted: { color: 'red', icon: <DeleteOutlined /> },
};

const STATE_LABEL: Record<ItemState, StringKey> = {
  live: 'itemStateLive',
  unavailable: 'itemStateUnavailable',
  deleted: 'itemStateDeleted',
};

const STATE_HINT: Record<ItemState, StringKey> = {
  live: 'itemStateLiveHint',
  unavailable: 'itemStateUnavailableHint',
  deleted: 'itemStateDeletedHint',
};

export function ItemStateTag({ item }: { item: Pick<Item, 'deleted_at' | 'is_available'> }) {
  const { lang } = useLang();
  const state = itemState(item);
  const { color, icon } = STATE_TAG[state];

  return (
    <Tooltip title={t(STATE_HINT[state], lang)}>
      {/* Tag renders a span, which cannot take a mouse handler on its own —
          Tooltip needs a focusable/ref-able child to anchor to. */}
      <Tag color={color} icon={icon} style={{ margin: 0 }}>
        {t(STATE_LABEL[state], lang)}
      </Tag>
    </Tooltip>
  );
}

/** Exported so list filters can offer the same vocabulary as the badge. */
export const ITEM_STATE_VALUES: ItemState[] = ['live', 'unavailable', 'deleted'];