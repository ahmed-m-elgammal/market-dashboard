/**
 * Recent orders table.
 *
 * All statuses, newest first — an operator wants to see what just came in,
 * including failures. Status and payment colours come from the shared token map
 * rather than being chosen inline.
 *
 * A NOTE ON THE NAME COLUMNS, because it looks like an oversight and is not.
 * get_recent_orders hardcodes `m.name_en` for the merchant and reads a single
 * `profiles.full_name` for the customer — the RPC has no *_ar variant of either,
 * because profiles has just the one full_name column. So on the live provider
 * these two columns are English-only, in Arabic mode too.
 *
 * pickName() is used rather than the raw column so that the demo provider's
 * Arabic variants are picked up when present and the live path degrades to
 * exactly what it renders today. That keeps the gap visible in the data rather
 * than hidden behind a translation that has nothing to translate.
 */
import { Card, Empty, Space, Spin, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import type { RecentOrder } from '../../constants';
import { PAYMENT_TAG_COLOR, STATUS_TAG_COLOR } from '../../theme/tokens';
import { useLang, useNumberLocale } from '../../i18n/LangProvider';
import { pickName, t, tStatus } from '../../i18n/strings';

export function RecentOrdersTable({
  rows,
  isLoading,
  currencyFormatter,
}: {
  rows: RecentOrder[] | undefined;
  isLoading: boolean;
  currencyFormatter: (value: number) => string;
}) {
  const { lang } = useLang();
  const numberLocale = useNumberLocale();

  const dateFormat = new Intl.DateTimeFormat(numberLocale, {
    dateStyle: 'medium',
    timeStyle: 'short',
  });

  const columns: ColumnsType<RecentOrder> = [
    {
      title: t('colOrderNumber', lang),
      dataIndex: 'order_number',
      key: 'order_number',
      render: (value: string | null) => value ?? '—',
    },
    {
      title: t('colCustomer', lang),
      key: 'customer',
      render: (_: unknown, row) => (
        <Typography.Text>
          {pickName(row.customer_name, row.customer_name_ar, lang) ||
            row.customer_phone ||
            '—'}
        </Typography.Text>
      ),
    },
    {
      title: t('colMerchant', lang),
      key: 'merchant',
      render: (_: unknown, row) => (
        <Space direction="vertical" size={0}>
          <Typography.Text>
            {pickName(row.merchant_name, row.merchant_name_ar, lang) || '—'}
          </Typography.Text>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            {row.merchant_city ?? ''}
          </Typography.Text>
        </Space>
      ),
    },
    {
      title: t('colItems', lang),
      dataIndex: 'item_count',
      key: 'item_count',
      align: 'right',
      width: 80,
    },
    {
      title: t('colTotal', lang),
      dataIndex: 'total',
      key: 'total',
      align: 'right',
      render: (value: number) => currencyFormatter(Number(value)),
    },
    {
      title: t('colStatus', lang),
      dataIndex: 'status',
      key: 'status',
      render: (status: RecentOrder['status']) => (
        <Tag color={STATUS_TAG_COLOR[status] ?? 'default'}>
          {tStatus('status', status, lang)}
        </Tag>
      ),
    },
    {
      title: t('colPayment', lang),
      dataIndex: 'payment_status',
      key: 'payment_status',
      render: (status: string) => (
        <Tag color={PAYMENT_TAG_COLOR[status] ?? 'default'}>
          {tStatus('payment', status, lang)}
        </Tag>
      ),
    },
    {
      title: t('colPlacedAt', lang),
      dataIndex: 'created_at',
      key: 'created_at',
      render: (value: string) => dateFormat.format(new Date(value)),
    },
  ];

  return (
    <Card
      title={t('recentOrdersTitle', lang)}
      variant="outlined"
      styles={{ body: { padding: 0 } }}
    >
      <Spin spinning={isLoading}>
        {rows && rows.length > 0 ? (
          <Table<RecentOrder>
            rowKey="id"
            size="small"
            columns={columns}
            dataSource={rows}
            pagination={false}
            scroll={{ x: 'max-content' }}
          />
        ) : (
          <Empty description={t('noData', lang)} style={{ padding: 24 }} />
        )}
      </Spin>
    </Card>
  );
}