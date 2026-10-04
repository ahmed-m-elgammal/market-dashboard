/**
 * Trending products table — top items by revenue over the last 7 days.
 *
 * Delivered orders only (migration 120): a trending list built on pending
 * orders would surface whatever was ordered most recently, and a cancelled
 * order is not demand. The window is fixed at 7 days by product decision, which
 * the subtitle states so it cannot be misread as following the KPI range above.
 *
 * Full width and three columns would be sparse, so the two things an operator
 * asks about a trending item — what it sells for, and which menu it is in — are
 * carried as columns rather than as a subtitle under the name.
 */
import { Card, Empty, Space, Spin, Table, Tag, Typography } from 'antd';
import { TagOutlined } from '@ant-design/icons';
import type { ColumnsType } from 'antd/es/table';
import type { TrendingItem } from '../../constants';
import { ItemThumb } from '../common/ItemThumb';
import { useLang } from '../../i18n/LangProvider';
import { pickName, t } from '../../i18n/strings';

export function TrendingItemsTable({
  rows,
  isLoading,
  currencyFormatter,
}: {
  rows: TrendingItem[] | undefined;
  isLoading: boolean;
  currencyFormatter: (value: number) => string;
}) {
  const { lang } = useLang();

  const columns: ColumnsType<TrendingItem> = [
    {
      title: t('colProduct', lang),
      dataIndex: 'name_en',
      key: 'name',
      render: (_: unknown, row) => (
        <Space>
          <ItemThumb name={pickName(row.name_en, row.name_ar, lang)} size={32} />
          <Typography.Text strong>{pickName(row.name_en, row.name_ar, lang)}</Typography.Text>
        </Space>
      ),
    },
    {
      title: t('colCategory', lang),
      key: 'category',
      width: 200,
      // pickName, not row.category_en directly: the Arabic label is absent on
      // the live provider and present in the demo, and this is the one call that
      // degrades correctly between them.
      render: (_: unknown, row) =>
        pickName(row.category_en, row.category_ar, lang) || '—',
    },
    {
      title: t('colUnits', lang),
      dataIndex: 'units_sold',
      key: 'units_sold',
      align: 'right',
      width: 100,
    },
    {
      title: t('colTotal', lang),
      dataIndex: 'revenue',
      key: 'revenue',
      align: 'right',
      width: 200,
      // The figure here is REVENUE — money this item earned over the window —
      // not the item's price. An earlier version stacked the item's
      // discount_price underneath it, which put two unrelated numbers in one
      // cell with nothing to say which was which; an operator compared them and
      // drew a conclusion about the discount that was meaningless.
      //
      // So the promotion is stated as a flag, not a figure. The saving is
      // quantified on the item's own screen, where the price it applies to is
      // the number next to it.
      render: (value: number, row) => (
        <Space direction="vertical" size={2} style={{ alignItems: 'flex-end' }}>
          <Typography.Text strong>{currencyFormatter(Number(value))}</Typography.Text>
          {row.discount_price !== null && (
            // A PRESET, not a token: Ant Design's Tag treats `color` as a
            // background, so passing colorInfoBg painted a pale blue wash with
            // pale text on it — present in the DOM and unreadable on screen. It
            // also matched nothing else in the app, so 'magenta' is used to stay
            // consistent with the promotion tag on the items table.
            <Tag color="magenta" icon={<TagOutlined />} style={{ marginInlineEnd: 0 }}>
              {t('onPromotion', lang)}
            </Tag>
          )}
        </Space>
      ),
    },
  ];

  return (
    <Card
      title={t('trendingTitle', lang)}
      variant="outlined"
      styles={{ body: { padding: 0 } }}
      extra={
        <Typography.Text type="secondary" style={{ fontSize: 12 }}>
          {t('trendingHint', lang)}
        </Typography.Text>
      }
    >
      <Spin spinning={isLoading}>
        {rows && rows.length > 0 ? (
          <Table<TrendingItem>
            rowKey="item_id"
            size="small"
            columns={columns}
            dataSource={rows}
            pagination={false}
          />
        ) : (
          <Empty description={t('noData', lang)} style={{ padding: 24 }} />
        )}
      </Spin>
    </Card>
  );
}