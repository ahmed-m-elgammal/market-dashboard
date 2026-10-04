/**
 * Overview — the dashboard landing page.
 *
 * Four KPI cards, three daily-series charts, recent orders and trending products.
 *
 * The 7/30/90 control drives BOTH the KPI cards and the charts from one
 * `days` value, so they always describe the same window. Trending is fixed at 7
 * days by product decision and is labelled as such, because mixing a fixed
 * window into a variable one without saying so is how a dashboard misleads.
 */
import { useMemo, useState } from 'react';
import { useList } from '@refinedev/core';
import { Alert, Col, Flex, Row, Segmented, Space, Typography } from 'antd';
import {
  RANGE_OPTIONS,
  RANGE_LABEL_KEYS,
  DEFAULT_RANGE,
  type DailySeriesRow,
  type PlatformKpis,
  type RangeDays,
  type RecentOrder,
  type TrendingItem,
} from '../../constants';
import { KpiCard } from '../../components/overview/KpiCard';
import { OverviewCharts } from '../../components/overview/OverviewCharts';
import { RecentOrdersTable } from '../../components/overview/RecentOrdersTable';
import { TrendingItemsTable } from '../../components/overview/TrendingItemsTable';
import { useLang } from '../../i18n/LangProvider';
import { countFormatter, currencyFormatter, fmt, t } from '../../i18n/strings';

export function OverviewPage() {
  const { lang } = useLang();
  const [days, setDays] = useState<RangeDays>(DEFAULT_RANGE);

  // ar-EG renders EGP as "ج.م. ١٢٬٣٤٥", en-EG as "EGP 12,345" — same number,
  // script-appropriate digits.
  const formatCurrency = useMemo(() => currencyFormatter(lang), [lang]);
  const formatCount = useMemo(() => countFormatter(lang), [lang]);

  const kpis = useList<PlatformKpis>({
    resource: 'overview-kpis',
    meta: { days },
  });
  const series = useList<DailySeriesRow>({
    resource: 'overview-series',
    meta: { days },
  });
  const trending = useList<TrendingItem>({
    resource: 'overview-trending',
    meta: { limit: 10 },
  });
  const recent = useList<RecentOrder>({
    resource: 'overview-recent-orders',
    meta: { limit: 10 },
  });

  // get_platform_kpis is an aggregate: one row, wrapped into an array by the
  // dataProvider so useList has the shape it expects.
  const k = kpis.data?.data[0];

  return (
    <Flex vertical gap={16}>
      <Flex align="center" justify="space-between" wrap gap={12}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          {t('overviewTitle', lang)}
        </Typography.Title>

        <Space>
          <Typography.Text type="secondary">{t('rangeLabel', lang)}</Typography.Text>
          <Segmented<RangeDays>
            value={days}
            onChange={setDays}
            options={RANGE_OPTIONS.map((d) => ({
              label: t(RANGE_LABEL_KEYS[d], lang),
              value: d,
            }))}
          />
        </Space>
      </Flex>

      {kpis.error && (
        <Alert
          type="error"
          showIcon
          message={t('loadFailed', lang)}
          description={kpis.error.message}
        />
      )}

      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} xl={6}>
          <KpiCard
            title={t('kpiRevenue', lang)}
            value={Number(k?.revenue ?? 0)}
            change={k?.change?.revenue ?? null}
            hint={t('kpiRevenueHint', lang)}
            format={formatCurrency}
            loading={kpis.isLoading}
          />
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <KpiCard
            title={t('kpiOrders', lang)}
            value={Number(k?.orders_count ?? 0)}
            change={k?.change?.orders_count ?? null}
            hint={t('kpiOrdersHint', lang)}
            format={formatCount}
            loading={kpis.isLoading}
          />
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <KpiCard
            title={t('kpiNewCustomers', lang)}
            value={Number(k?.new_customers ?? 0)}
            change={k?.change?.new_customers ?? null}
            format={formatCount}
            loading={kpis.isLoading}
          />
        </Col>
        <Col xs={24} sm={12} xl={6}>
          <KpiCard
            title={t('kpiActiveCustomers', lang)}
            value={Number(k?.active_customers ?? 0)}
            // No change figure: the RPC has no previous-window baseline for
            // active customers, so this card shows no trend rather than a fake 0%.
            change={null}
            format={formatCount}
            loading={kpis.isLoading}
          />
        </Col>
      </Row>

      {/* Cancelled orders are excluded from revenue AND order count (migration
          120). Surfaced here so the two cards can be reconciled by eye. */}
      {Number(k?.cancelled_count ?? 0) > 0 && (
        <Alert
          type="info"
          showIcon
          message={fmt(t('cancelledHidden', lang), { n: formatCount(k?.cancelled_count ?? 0) })}
        />
      )}

      <OverviewCharts
        rows={series.data?.data}
        isLoading={series.isLoading}
        days={days}
        currencyFormatter={formatCurrency}
      />

      {/*
        Recent orders and Trending products are STACKED, full width, in that
        order.

        They were side by side (14/10) and both were unreadable: Recent orders
        has eight columns, so in 58% of the width its Status, Payment and Placed
        columns were scrolled off the right edge — the three columns an operator
        opened the panel to read. Trending has three columns, which in 42% of the
        width left its Total column against the card edge.

        Stacking gives each table the full width it needs and matches the order
        the panels were specified in: graphs, then recent orders, then trending.
      */}
      <RecentOrdersTable
        rows={recent.data?.data}
        isLoading={recent.isLoading}
        currencyFormatter={formatCurrency}
      />

      <TrendingItemsTable
        rows={trending.data?.data}
        isLoading={trending.isLoading}
        currencyFormatter={formatCurrency}
      />

      {series.error && (
        <Alert
          type="warning"
          showIcon
          message={t('loadFailed', lang)}
          description={series.error.message}
        />
      )}
      {trending.error && <Alert type="warning" showIcon message={trending.error.message} />}
      {recent.error && <Alert type="warning" showIcon message={recent.error.message} />}
    </Flex>
  );
}