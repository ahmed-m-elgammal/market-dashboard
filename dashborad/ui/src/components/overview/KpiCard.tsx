/**
 * KPI card: a value, a comparison against the previous window, and a hint.
 *
 * The percentage change is NULL when the previous window was empty — a dashboard
 * that renders "0%" against no baseline says "flat" when the truth is "this is
 * new". That case gets its own "New" tag rather than 0%, because a new operator
 * seeing 0% on every card would assume the dashboard is broken.
 */
import { Card, Flex, Statistic, Tag, Tooltip, Typography } from 'antd';
import { ArrowDownOutlined, ArrowUpOutlined, InfoCircleOutlined } from '@ant-design/icons';
import { useSemanticColors } from '../../theme/tokens';
import { useLang } from '../../i18n/LangProvider';
import { t } from '../../i18n/strings';

export interface KpiCardProps {
  title: string;
  value: number;
  /** Percentage change vs the previous window, or null when there is no baseline. */
  change: number | null;
  hint?: string;
  precision?: number;
  loading?: boolean;
  /** Currency formats the value and the trend percentage; omit for plain counts. */
  /**
 * Formats the value. AntD's Statistic formatter is generic over valueType, so
 * this is typed to number|string at the call boundary.
 */
format?: (value: number) => string;
}

export function KpiCard({
  title,
  value,
  change,
  hint,
  precision = 0,
  loading,
  format,
}: KpiCardProps) {
  const { lang } = useLang();
  const colors = useSemanticColors();

  const direction = change === null || change === 0 ? 'flat' : change > 0 ? 'up' : 'down';

  // Semantic tokens, not 'green'/'red' presets — see theme/tokens.ts.
  // change is already known non-null whenever direction !== 'flat', but the
  // narrowing lives in `direction`, so assert once here rather than repeat the
  // ternary chain.
  const trendPercent = change === null ? 0 : Math.abs(change);

  const trendColor =
    direction === 'up'
      ? colors.colorPositive
      : direction === 'down'
        ? colors.colorNegative
        : change === null
          ? colors.colorNeutralSoft
          : colors.colorNeutral;

  const trend =
    direction === 'flat' ? (
      <Tag color={trendColor} bordered={false}>
        {change === null ? t('trendNew', lang) : t('trendFlat', lang)}
      </Tag>
    ) : (
      <Tag color={trendColor} bordered={false}>
        {direction === 'up' ? <ArrowUpOutlined /> : <ArrowDownOutlined />} {trendPercent}%
      </Tag>
    );

  return (
    <Card loading={loading} variant="outlined" style={{ height: '100%' }}>
      <Flex vertical gap={8}>
        <Flex align="center" gap={6} justify="space-between">
          <Typography.Text type="secondary">{title}</Typography.Text>
          {hint && (
            <Tooltip title={hint}>
              <InfoCircleOutlined style={{ color: colors.colorMuted }} />
            </Tooltip>
          )}
        </Flex>

        <Flex align="baseline" gap={8} wrap>
          <Statistic
            value={value}
            // precision is ignored once a formatter is supplied, so the two
            // paths cannot both apply and double-format the number.
            precision={format ? undefined : precision}
            formatter={format ? (v) => format(Number(v)) : undefined}
            valueStyle={{ fontSize: 24, fontWeight: 600 }}
          />
          {trend}
        </Flex>
      </Flex>
    </Card>
  );
}