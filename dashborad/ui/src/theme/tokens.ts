/**
 * Semantic colour tokens.
 *
 * No raw hex anywhere in the components. Everything resolves through Ant
 * Design's design tokens via useToken(), so light mode, dark mode and any future
 * theme change are picked up automatically — a hardcoded '#bfbfbf' would stay
 * grey in dark mode where the surrounding text goes light.
 *
 * Use the semantic name (colorMuted, colorPositive) rather than a preset
 * ('green', 'red') at the call site: presets are palette entries and carry no
 * meaning, so swapping the palette would silently repaint every status.
 */
import { theme } from 'antd';
import type { OrderStatus } from '../constants';

export interface SemanticColors {
  /** De-emphasised text and icons: hints, column captions. */
  colorMuted: string;
  /** Positive movement. */
  colorPositive: string;
  /** Negative movement. */
  colorNegative: string;
  /** Neutral movement. */
  colorNeutral: string;
  /** "No baseline yet" — deliberately distinct from positive and negative. */
  colorNeutralSoft: string;
  /** Border for outlined surfaces. */
  colorBorder: string;
}

/**
 * Must be called inside a component (it consumes AntD context).
 */
export function useSemanticColors(): SemanticColors {
  const { token } = theme.useToken();
  return {
    colorMuted: token.colorTextQuaternary,
    colorPositive: token.colorSuccess,
    colorNegative: token.colorError,
    colorNeutral: token.colorTextSecondary,
    colorNeutralSoft: token.colorInfoBg,
    colorBorder: token.colorBorderSecondary,
  };
}

/**
 * Order status -> Ant Design preset tag colour.
 *
 * Presets rather than tokens because Tag colours ARE presets in Ant Design's
 * API. This map is the single place status colour is decided — the status Tag
 * components read from it rather than branching inline.
 */
export const STATUS_TAG_COLOR: Record<OrderStatus, string> = {
  pending: 'default',
  confirmed: 'blue',
  preparing: 'geekblue',
  ready: 'cyan',
  picked_up: 'purple',
  on_the_way: 'gold',
  delivered: 'green',
  cancelled: 'red',
};

/** Payment status -> preset. Same single-source rule as order status. */
export const PAYMENT_TAG_COLOR: Record<string, string> = {
  pending: 'default',
  pending_cash: 'gold',
  paid: 'green',
  failed: 'red',
  refunded: 'purple',
  pending_refund: 'gold',
  partial_refund: 'orange',
  refund_failed: 'red',
};