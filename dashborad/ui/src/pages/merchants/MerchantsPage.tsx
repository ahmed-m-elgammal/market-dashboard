/**
 * Merchants — the list, with a create modal.
 *
 * WHY A MODAL FOR CREATE AND A ROUTE FOR VIEW
 *   Creating a merchant is a short, self-contained task whose result is a row in
 *   the list you were already looking at. A route would mean leaving the list to
 *   fill a form and navigating back to see the outcome — two extra steps for no
 *   gain. Opening an EXISTING merchant is different: it is a longer read of a
 *   record, so it gets a page of its own.
 *
 * WHY THE COUNTS ARE ON THE ROW
 *   category_count and item_count come from the provider rather than a second
 *   round trip per merchant. They answer the question an operator actually has
 *   while scanning this list — "which of these vendors even has a menu?" — without
 *   a detail navigation. A merchant with zero items is the one worth noticing, so
 *   it is styled as a warning rather than shown as a plain zero.
 */
import { useMemo, useState } from 'react';
import { useCreate, useGetIdentity } from '@refinedev/core';
import { App, Button, Card, Input, Space, Table, Tag, Tooltip, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { PlusOutlined, ReloadOutlined, ShopOutlined } from '@ant-design/icons';
import type { Merchant, MerchantCategoryCode, MerchantInput } from '../../constants';
import { MERCHANT_CATEGORY_META } from '../../demo/merchantCategories';
import { MerchantFormModal } from '../../components/merchants/MerchantFormModal';
import { MerchantLogo } from '../../components/common/ItemThumb';
import { useResourceTable } from '../../hooks/useResourceTable';
import { useLang, useNumberLocale } from '../../i18n/LangProvider';
import { countFormatter, fmt, pickName, ratingFormatter, t, tStatus } from '../../i18n/strings';

/**
 * Merchant category code -> its display name.
 *
 * merchants.category holds a code from merchant_categories (migration 097), not
 * a label, so rendering the column raw would show "grocery" beside an Arabic name
 * in Arabic mode. The lookup falls back to the code so a category added by a
 * later migration still shows something rather than a blank cell.
 */
const CATEGORY_LABEL = new Map(MERCHANT_CATEGORY_META.map((c) => [c.code, c]));

function categoryLabel(code: string, lang: 'en' | 'ar'): string {
  const meta = CATEGORY_LABEL.get(code as MerchantCategoryCode);
  return meta ? pickName(meta.name_en, meta.name_ar, lang) : code;
}

/** Merchant row as the provider returns it: a Merchant plus four counts. */
export interface MerchantRow extends Merchant {
  category_count: number;
  item_count: number;
  unavailable_item_count: number;
  deleted_item_count: number;
}

/**
 * Approval colour per status. Presets, because Tag's API takes presets — the same
 * rule STATUS_TAG_COLOR follows in theme/tokens.ts.
 *
 * pending is gold rather than orange so it reads as "waiting on a human" rather
 * than as a warning about something already wrong.
 */
const APPROVAL_TAG: Record<string, string> = {
  pending: 'gold',
  approved: 'green',
  rejected: 'red',
};

export function MerchantsPage() {
  const { lang } = useLang();
  const locale = useNumberLocale();
  const { message } = App.useApp();
  const { data: identity } = useGetIdentity<{ role: string }>();

  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);

  const { data, total, tableProps, refetch } = useResourceTable<MerchantRow>({
    resource: 'merchants',
    pagination: { current: 1, pageSize: 10 },
    sorters: { initial: [{ field: 'name_en', order: 'asc' }] },
    // The search box lives outside the table, so its value travels in through
    // meta. Kept in component state rather than the URL deliberately: each screen
    // has its own search box, and sharing one across routes would make the back
    // button behave inconsistently between them.
    meta: { search },
  });

  const { mutate: createMerchant, isLoading: isCreating } = useCreate<MerchantInput>();

  const number = useMemo(() => countFormatter(lang), [lang]);
  const rating = useMemo(() => ratingFormatter(lang), [lang]);
  const dateFormat = useMemo(
    () => new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }),
    [locale],
  );

  const onSubmit = (values: MerchantInput) => {
    createMerchant(
      { resource: 'merchants', values },
      {
        onSuccess: () => {
          setFormOpen(false);
          message.success(t('merchantCreatedToast', lang));
        },
        // The provider's DemoValidationError carries both scripts, so the message
        // follows the UI language instead of always arriving in English.
        onError: (error: unknown) => {
          const e = error as { messageAr?: string; message?: string };
          message.error(
            (lang === 'ar' ? e.messageAr : e.message) ?? t('unexpectedError', lang),
          );
        },
      },
    );
  };

  const columns: ColumnsType<MerchantRow> = [
    {
      title: t('merchantsTitle', lang),
      key: 'merchant',
      fixed: 'left',
      render: (_, row) => (
        <Space direction="vertical" size={0}>
          <Space size={8}>
            <MerchantLogo name={pickName(row.name_en, row.name_ar, lang)} size={32} />
            <Typography.Text strong>{pickName(row.name_en, row.name_ar, lang)}</Typography.Text>
          </Space>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            {[row.area, row.city].filter(Boolean).join(', ')}
          </Typography.Text>
        </Space>
      ),
    },
    {
      title: t('fieldCategory', lang),
      dataIndex: 'category',
      key: 'category',
      render: (code: string) => <Tag>{categoryLabel(code, lang)}</Tag>,
    },
    {
      title: t('categoriesAndItems', lang),
      key: 'counts',
      align: 'right',
      render: (_, row) => (
        // "categories / items". A vendor with no live items is the actionable
        // signal on this screen, so it is called out rather than shown as 0.
        <Space size={4}>
          <span>{number(row.category_count)}</span>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            /
          </Typography.Text>
          <Typography.Text
            type={row.item_count === 0 ? 'danger' : undefined}
            style={row.item_count === 0 ? { fontWeight: 600 } : undefined}
          >
            {number(row.item_count)}
          </Typography.Text>
          {row.unavailable_item_count > 0 && (
            <Tooltip title={t('stateUnavailable', lang)}>
              <Tag color="orange" bordered={false}>
                {number(row.unavailable_item_count)}
              </Tag>
            </Tooltip>
          )}
        </Space>
      ),
    },
    {
      title: t('colStatus', lang),
      key: 'status',
      render: (_, row) => (
        <Space direction="vertical" size={2}>
          <Tag color={APPROVAL_TAG[row.approval_status] ?? 'default'}>
            {tStatus('approval', row.approval_status, lang)}
          </Tag>
          <Tag color={row.is_active ? 'default' : 'red'} bordered={false}>
            {row.is_active ? t('statusActive', lang) : t('statusInactive', lang)}
          </Tag>
        </Space>
      ),
    },
    {
      title: t('ratingLabel', lang),
      key: 'rating',
      align: 'right',
      sorter: true,
      render: (_, row) => (
        <Tooltip title={fmt(t('ratingCount', lang), { n: number(row.rating_count) })}>
          <span>{rating(row.rating)}</span>
        </Tooltip>
      ),
    },
    {
      title: t('merchantCreated', lang),
      dataIndex: 'created_at',
      key: 'created_at',
      sorter: true,
      render: (value: string) => dateFormat.format(new Date(value)),
    },
    {
      title: t('colActions', lang),
      key: 'actions',
      fixed: 'right',
      render: (_, row) => (
        <Button type="link" size="small" href={`/merchants/${row.id}`}>
          {t('merchantDetails', lang)}
        </Button>
      ),
    },
  ];

  return (
    <>
      <Card
        variant="outlined"
        title={
          <Space>
            <ShopOutlined />
            {t('merchantsTitle', lang)}
            {data.length > 0 && (
              <Typography.Text type="secondary" style={{ fontWeight: 400 }}>
                {fmt(t('merchantsCount', lang), { n: total })}
              </Typography.Text>
            )}
          </Space>
        }
        extra={
          <Space wrap>
            <Input.Search
              allowClear
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={t('merchantSearchPlaceholder', lang)}
              style={{ width: 300 }}
            />
            <Tooltip title={t('retry', lang)}>
              <Button icon={<ReloadOutlined />} onClick={() => void refetch()} />
            </Tooltip>
            <Button
              type="primary"
              icon={<PlusOutlined />}
              onClick={() => setFormOpen(true)}
              // Disabled rather than hidden when the caller is not an admin: a
              // control that silently vanishes is harder to diagnose than one
              // that is visibly unavailable. The demo identity is always an
              // admin, so this never fires today — it is here for the live
              // provider, where the role is read from profiles.
              disabled={identity?.role !== 'admin'}
            >
              {t('addMerchant', lang)}
            </Button>
          </Space>
        }
      >
        <Table<MerchantRow>
          {...tableProps}
          rowKey="id"
          size="small"
          columns={columns}
          scroll={{ x: 'max-content' }}
        />
      </Card>

      <MerchantFormModal
        open={formOpen}
        onCancel={() => setFormOpen(false)}
        onSubmit={onSubmit}
        confirmLoading={isCreating}
      />
    </>
  );
}