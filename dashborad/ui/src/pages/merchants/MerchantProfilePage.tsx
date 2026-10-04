/**
 * Merchant profile — everything about one merchant on one page.
 *
 * Layout follows how the record is actually read: identity at the top (name,
 * status, rating), then contact and payout, then delivery settings beside a menu
 * summary that links into the category drill-down.
 *
 * Sections use Descriptions rather than a form because the fields are read-only
 * here — every one is editable through the Edit action, and a read-only form
 * would imply the values could be changed in place.
 *
 * Every row comes from a real column in constants.ts. Nothing here invents a
 * field: if merchants has no "tax id" column there is no tax id row, because a
 * dashboard showing a plausible-but-empty field is worse than one showing
 * nothing.
 */
import { useMemo, useState } from 'react';
import { useOne, useUpdate } from '@refinedev/core';
import {
  Alert,
  Button,
  Card,
  Col,
  Descriptions,
  Empty,
  Flex,
  List,
  Row,
  Space,
  Spin,
  Tag,
  Tooltip,
  Typography,
} from 'antd';
import type { DescriptionsProps } from 'antd';
import { ArrowLeftOutlined, EditOutlined, ShopOutlined } from '@ant-design/icons';
import type { Category, MerchantCategoryCode, MerchantInput } from '../../constants';
import { MERCHANT_CATEGORY_META } from '../../demo/merchantCategories';
import type { MerchantRow } from './MerchantsPage';
import { MerchantFormModal } from '../../components/merchants/MerchantFormModal';
import { MerchantStateActions } from '../../components/merchants/MerchantStateActions';
import { MerchantLogo } from '../../components/common/ItemThumb';
import { useResourceTable } from '../../hooks/useResourceTable';
import { useLang, useNumberLocale } from '../../i18n/LangProvider';
import {
  countFormatter,
  currencyFormatter,
  errorText,
  fmt,
  pickName,
  ratingFormatter,
  t,
  tStatus,
} from '../../i18n/strings';

/** Category row with the counts the profile's menu summary shows. */
interface CategorySummary extends Category {
  item_count: number;
  unavailable_item_count: number;
}

/**
 * merchants.category is a code from merchant_categories (migration 097), not a
 * label — so the raw code is never shown. Falls back to the code for a category
 * a later migration adds, which is degraded but never blank.
 */
const CATEGORY_LABEL = new Map(MERCHANT_CATEGORY_META.map((c) => [c.code, c]));

function categoryLabel(code: string, lang: 'en' | 'ar'): string {
  const meta = CATEGORY_LABEL.get(code as MerchantCategoryCode);
  return meta ? pickName(meta.name_en, meta.name_ar, lang) : code;
}

export function MerchantProfilePage({ merchantId }: { merchantId: string }) {
  const { lang } = useLang();
  const locale = useNumberLocale();
  const [editing, setEditing] = useState(false);

  /** useOne wraps the record: `data` is `{ data: T }`. Unwrapped once, here. */
const { data: response, isLoading, error } = useOne<MerchantRow>({
    resource: 'merchants',
    id: merchantId,
  });
  const merchant = response?.data;
  const { mutate: updateMerchant, isLoading: isSaving } = useUpdate<MerchantInput>();

  const categories = useResourceTable<CategorySummary>({
    resource: 'merchant-categories',
    pagination: { current: 1, pageSize: 100 },
    meta: { merchantId },
    queryOptions: { enabled: Boolean(merchantId) },
  });

  const currency = useMemo(() => currencyFormatter(lang), [lang]);
  const number = useMemo(() => countFormatter(lang), [lang]);
  const rating = useMemo(() => ratingFormatter(lang), [lang]);
  const dateFormat = useMemo(
    () => new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }),
    [locale],
  );

  if (isLoading) {
    return (
      <Card variant="outlined">
        <Spin />
      </Card>
    );
  }

  if (error || !merchant) {
    return (
      <Alert
        type="error"
        showIcon
        message={t('merchantNotFound', lang)}
        description={errorText(error, lang)}
        action={
          <Button href="/merchants" icon={<ArrowLeftOutlined />}>
            {t('backToMerchants', lang)}
          </Button>
        }
      />
    );
  }

  const m = merchant;

  const onSubmit = (values: MerchantInput) => {
    updateMerchant(
      { resource: 'merchants', id: m.id, values },
      {
        onSuccess: () => {
          setEditing(false);
          // No toast here: the modal closing IS the confirmation, and a second
          // success message underneath it competes with the page it just
          // updated.
        },
        onError: (updateError: unknown) => {
          const e = updateError as { messageAr?: string; message?: string };
          // Surfaced through the modal's inline Alert rather than a toast,
          // because the modal stays open and the message belongs next to the
          // fields that caused it.
          setEditing(true);
          throw e;
        },
      },
    );
  };

  const detailItems: DescriptionsProps['items'] = [
    { key: 'name_en', label: t('fieldNameEn', lang), children: m.name_en },
    { key: 'name_ar', label: t('fieldNameAr', lang), children: m.name_ar },
    { key: 'category', label: t('fieldCategory', lang), children: <Tag>{categoryLabel(m.category, lang)}</Tag> },
    {
      key: 'rating',
      label: t('ratingLabel', lang),
      children: (
        <Tooltip title={fmt(t('ratingCount', lang), { n: number(m.rating_count) })}>
          <span>{rating(m.rating)}</span>
        </Tooltip>
      ),
    },
    {
      key: 'created_at',
      label: t('merchantCreated', lang),
      children: dateFormat.format(new Date(m.created_at)),
    },
    {
      key: 'description',
      label: t('fieldDescriptionEn', lang),
      // Both scripts shown whichever the UI language: an operator checking a
      // translation needs them side by side, not one at a time.
      span: 2,
      children: (
        <Space direction="vertical" size={0}>
          <Typography.Text>{m.description_en || '—'}</Typography.Text>
          {m.description_ar && (
            <Typography.Text type="secondary" dir="rtl">
              {m.description_ar}
            </Typography.Text>
          )}
        </Space>
      ),
    },
  ];

  const contactItems: DescriptionsProps['items'] = [
    { key: 'phone', label: t('fieldPhone', lang), children: m.phone },
    { key: 'address', label: t('fieldAddress', lang), children: m.address },
    {
      key: 'city',
      label: t('fieldCity', lang),
      children: [m.city, m.area].filter(Boolean).join(' — '),
    },
    {
      key: 'coords',
      label: `${t('fieldLat', lang)} / ${t('fieldLng', lang)}`,
      children: `${m.lat}, ${m.lng}`,
    },
  ];

  const payoutItems: DescriptionsProps['items'] = [
    {
      key: 'frequency',
      label: t('fieldPayoutFrequency', lang),
      // The raw column holds a CHECK-constraint token ('weekly'), which is an
      // identifier rather than something to show an operator.
      children: tStatus('status', m.payout_frequency, lang),
    },
    {
      key: 'method',
      label: t('fieldPayoutMethod', lang),
      children: tStatus('status', m.payout_method, lang),
    },
    {
      key: 'wallet',
      label: t('fieldWalletPhone', lang),
// Shown for every payout method, not only wallet: the column can hold a
      // number regardless, and hiding it would make a filled-in wallet phone
      // look deleted. "Not set" rather than a dash, so an absent value reads as
      // absent instead of as an empty-but-present one.
      children: m.wallet_phone ?? t('notSet', lang),
    },
    {
      key: 'commission',
      label: t('fieldCommission', lang),
      children: m.commission_pct === null ? '—' : `${m.commission_pct}%`,
    },
  ];

  const deliveryItems: DescriptionsProps['items'] = [
    {
      key: 'prep',
      label: t('fieldPrepMinutes', lang),
      children: number(m.estimated_prep_time_minutes),
    },
    {
      key: 'delivery',
      label: t('fieldDeliveryMinutes', lang),
      children: number(m.estimated_delivery_minutes),
    },
    {
      key: 'radius',
      label: t('fieldDeliveryRadius', lang),
      children: String(m.delivery_radius_km),
    },
    {
      key: 'min_order',
      label: t('fieldMinOrder', lang),
      children: currency(m.min_order_amount),
    },
    {
      key: 'fee',
      label: t('fieldDeliveryFee', lang),
      // Null is NOT zero. It means "use the platform default", and rendering it
      // as EGP 0 would state something the record does not say.
children:
        m.delivery_fee_override === null
          ? t('platformDefault', lang)
          : currency(m.delivery_fee_override),
    },
  ];

  return (
    <Flex vertical gap={16}>
      <Flex align="center" justify="space-between" wrap gap={12}>
        <Space wrap>
          <Button href="/merchants" icon={<ArrowLeftOutlined />}>
            {t('backToMerchants', lang)}
          </Button>
          <MerchantLogo name={pickName(m.name_en, m.name_ar, lang)} size={40} />
          <Typography.Title level={4} style={{ margin: 0 }}>
            {pickName(m.name_en, m.name_ar, lang)}
          </Typography.Title>
          <Tag color={m.approval_status === 'approved' ? 'green' : 'gold'}>
            {tStatus('approval', m.approval_status, lang)}
          </Tag>
          <Tag color={m.is_active ? 'default' : 'red'} bordered={false}>
            {m.is_active ? t('statusActive', lang) : t('statusInactive', lang)}
          </Tag>
        </Space>

        <Button type="primary" icon={<EditOutlined />} onClick={() => setEditing(true)}>
          {t('editMerchant', lang)}
        </Button>
      </Flex>

{/* A pending merchant is the one state that keeps a vendor off the
          platform, so it is stated at the top rather than left to be noticed in
          a table cell two scrolls down. */}
      {m.approval_status === 'pending' && (
        <Alert type="warning" showIcon message={t('approval_pending', lang)} />
      )}

      {/* Review and visibility. Sits above the details because approving is the
          next action an operator comes here to do, not something to scroll for. */}
      <MerchantStateActions merchant={m} />

      <Row gutter={[16, 16]}>
        <Col xs={24} xl={16}>
          <Flex vertical gap={16}>
            <Card title={t('merchantDetails', lang)} variant="outlined">
              <Descriptions size="small" column={{ xs: 1, sm: 2 }} items={detailItems} />
            </Card>

            <Card title={t('merchantContact', lang)} variant="outlined">
              <Descriptions size="small" column={{ xs: 1, sm: 2 }} items={contactItems} />
            </Card>

            <Card title={t('merchantPayout', lang)} variant="outlined">
              <Descriptions size="small" column={{ xs: 1, sm: 2 }} items={payoutItems} />
            </Card>
          </Flex>
        </Col>

        <Col xs={24} xl={8}>
          <Flex vertical gap={16}>
            <Card title={t('merchantDelivery', lang)} variant="outlined">
              <Descriptions size="small" column={1} items={deliveryItems} />
            </Card>

            <MenuSummary
              merchantId={m.id}
              data={categories.data}
              isLoading={categories.isLoading}
              error={categories.error as Error | null}
            />
          </Flex>
        </Col>
      </Row>

      <MerchantFormModal
        open={editing}
        merchant={m}
        onCancel={() => setEditing(false)}
        onSubmit={onSubmit}
        confirmLoading={isSaving}
      />
    </Flex>
  );
}

/**
 * The menu as one line per category, linking into the items screen.
 *
 * A summary rather than the full item list: this panel answers "what does this
 * vendor sell, and is the menu healthy", and reading 40 items is the items
 * screen's job. Kept to a line per category so the profile stays scannable.
 */
function MenuSummary({
  merchantId,
  data,
  isLoading,
  error,
}: {
  merchantId: string;
  data: CategorySummary[] | undefined;
  isLoading: boolean;
  error: Error | null;
}) {
  const { lang } = useLang();

  if (isLoading) {
    return (
      <Card variant="outlined">
        <Spin />
      </Card>
    );
  }

  if (error) {
    return (
      <Alert
        type="warning"
        showIcon
        message={t('loadFailed', lang)}
        description={error.message}
      />
    );
  }

  const rows = data ?? [];

  return (
    <Card
      title={
        <Space>
          <ShopOutlined />
          {t('categoriesTitle', lang)}
        </Space>
      }
      variant="outlined"
      styles={{ body: { padding: rows.length > 0 ? '8px 0' : 24 } }}
    >
      {rows.length === 0 ? (
        <Empty description={t('categoryEmpty', lang)} />
      ) : (
        <List
          size="small"
          dataSource={rows}
          renderItem={(category) => (
            <List.Item
              actions={[
                <Button
                  key="items"
                  type="link"
                  size="small"
                  href={`/merchants/${merchantId}/categories/${category.id}`}
                >
                  {t('categoryItemsAction', lang)}
                </Button>,
              ]}
            >
              <List.Item.Meta
                title={
                  <Space>
                    <Typography.Text>
                      {pickName(category.name_en, category.name_ar, lang)}
                    </Typography.Text>
                    {category.is_available ? null : (
                      <Tag color="orange" bordered={false}>
                        {t('stateUnavailable', lang)}
                      </Tag>
                    )}
                  </Space>
                }
                description={
                  <Typography.Text
                    // Empty categories are the actionable signal, so they are
                    // called out. type="danger" rather than a literal colour —
                    // see theme/tokens.ts.
                    type={category.item_count === 0 ? 'danger' : 'secondary'}
                    style={{ fontSize: 12 }}
                  >
                    {categorySummaryLabel(category, lang)}
                  </Typography.Text>
                }
              />
            </List.Item>
          )}
        />
      )}
    </Card>
  );
}

/** "{n} items · {n} unavailable" — both scripts come from strings.ts. */
function categorySummaryLabel(category: CategorySummary, lang: 'en' | 'ar'): string {
  const items = fmt(t('categoryItemsCount', lang), { n: category.item_count });
  if (category.unavailable_item_count === 0) return items;
  return `${items} · ${fmt(t('categoryUnavailableCount', lang), { n: category.unavailable_item_count })}`;
}