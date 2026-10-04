/**
 * Daily-series charts.
 *
 * Uses @ant-design/charts (G2). Three charts off ONE get_daily_series call, so
 * the x-axes are identical and the lines are comparable — fetching per chart
 * would risk three different day lists.
 *
 * The series already returns an explicit zero row for every day in the range
 * (generate_series in migration 120), so gaps render as real zeros rather than a
 * straight line across missing dates.
 */
import { Line } from '@ant-design/charts';
import { Card, Col, Empty, Row, Spin } from 'antd';
import type { DailySeriesRow } from '../../constants';
import { useLang, useNumberLocale } from '../../i18n/LangProvider';
import { t } from '../../i18n/strings';

interface SeriesChartProps {
  title: string;
  field: 'revenue' | 'orders_count' | 'new_customers';
  rows: DailySeriesRow[] | undefined;
  isLoading: boolean;
  valueFormatter?: (value: number) => string;
  /** Horizontal axis density: 90 days needs fewer ticks than 7. */
  tickCount?: number;
}

function SeriesChart({
  title,
  field,
  rows,
  isLoading,
  valueFormatter,
  tickCount,
}: SeriesChartProps) {
  const { lang } = useLang();

  const dateFormat = new Intl.DateTimeFormat(useNumberLocale(), {
    day: 'numeric',
    month: 'short',
  });

  const data = (rows ?? []).map((row) => ({
    day: row.day,
    [field]: row[field],
  }));

  return (
    <Card title={title} variant="outlined" style={{ height: '100%' }}>
      <Spin spinning={isLoading}>
        {data.length === 0 ? (
          <Empty description={t('noData', lang)} />
        ) : (
          <Line
            data={data}
            xField="day"
            yField={field}
            height={220}
            // No shapeField: the default 'line' is unsmoothed. A spline would
            // draw values between the daily points that never existed in the
            // data, which reads as real on a chart someone makes decisions from.
            style={{ lineWidth: 2 }}
            axis={{
              x: {
                title: false,
                labelAutoRotate: tickCount !== undefined,
                labelAutoHide: true,
                // 'day' is a raw YYYY-MM-DD string; formatting it here is what
                // keeps "2026-03-01" off the axis in every range.
                labelFormatter: (v: string) => {
                  const parsed = new Date(v);
                  return Number.isNaN(parsed.getTime()) ? v : dateFormat.format(parsed);
                },
                tickCount,
              },
              y: {
                title: t('axisValue', lang),
                labelFormatter: (v: string) =>
                  valueFormatter ? valueFormatter(Number(v)) : v,
              },
            }}
            tooltip={{
              // 'day' is the FIELD NAME, not a caption — G2 resolves it against
              // the data. A callback formats it, because axis.labelFormatter
              // does not reach the tooltip title and the raw YYYY-MM-DD would
              // otherwise show there.
              title: (datum: { day: string }) => {
                const parsed = new Date(datum.day);
                return Number.isNaN(parsed.getTime()) ? datum.day : dateFormat.format(parsed);
              },
              items: [
                {
                  channel: 'y',
                  valueFormatter: (v: number) =>
                    valueFormatter ? valueFormatter(v) : String(v),
                },
              ],
            }}
          />
        )}
      </Spin>
    </Card>
  );
}

export function OverviewCharts({
  rows,
  isLoading,
  days,
  currencyFormatter,
}: {
  rows: DailySeriesRow[] | undefined;
  isLoading: boolean;
  days: number;
  currencyFormatter: (value: number) => string;
}) {
  const { lang } = useLang();

  return (
    <Row gutter={[16, 16]}>
      <Col xs={24} lg={8}>
        <SeriesChart
          title={t('chartRevenueTitle', lang)}
          field="revenue"
          rows={rows}
          isLoading={isLoading}
          valueFormatter={currencyFormatter}
          tickCount={days <= 7 ? 7 : 6}
        />
      </Col>
      <Col xs={24} lg={8}>
        <SeriesChart
          title={t('chartOrdersTitle', lang)}
          field="orders_count"
          rows={rows}
          isLoading={isLoading}
          tickCount={days <= 7 ? 7 : 6}
        />
      </Col>
      <Col xs={24} lg={8}>
        <SeriesChart
          title={t('chartCustomersTitle', lang)}
          field="new_customers"
          rows={rows}
          isLoading={isLoading}
          tickCount={days <= 7 ? 7 : 6}
        />
      </Col>
    </Row>
  );
}