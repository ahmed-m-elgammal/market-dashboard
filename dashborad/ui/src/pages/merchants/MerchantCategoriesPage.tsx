/**
 * Categories for one merchant, and the item list for the selected category.
 *
 * This screen is the junction the flow calls for:
 *
 *   merchants -> profile -> CATEGORIES -> click one -> ITEMS -> click one -> item
 *
 * The category list and the item list live together on one route deliberately.
 * The operator's question is always "which items are in Drinks, and which of
 *   them are unavailable", and keeping both halves of that answer on one page
 *   leaves the category list visible as context while items are filtered, sorted
 *   and searched. Splitting them would mean navigating back and forth to answer
 *   a single question.
 *
 * The selected category lives in the URL (`?category=`), so a reload, a refresh
 * and a shared link all land on the same view.
 */
import { useMemo, useState } from 'react';
import { useCreate, useOne } from '@refinedev/core';
import {
  Alert,
  App,
  Button,
  Card,
  Col,
  Dropdown,
  Empty,
  Flex,
  Input,
  List,
  Row,
  Segmented,
  Space,
  Table,
  Tag,
  Tooltip,
  Typography,
  theme,
} from 'antd';
import type { MenuProps } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import {
  ArrowLeftOutlined,
  DeleteOutlined,
  EditOutlined,
  EyeOutlined,
  MoreOutlined,
  PlusOutlined,
  ReloadOutlined,
  StopOutlined,
  UndoOutlined,
} from '@ant-design/icons';
import { useSearchParams } from 'react-router';
import { itemState, type Category, type Item, type ItemInput } from '../../constants';

import { ItemStateTag } from '../../components/items/ItemStateTag';
import { ItemThumb } from '../../components/common/ItemThumb';
import { ItemFormModal } from '../../components/items/ItemFormModal';
import { useItemActions } from '../../hooks/useItemActions';
import type { MerchantRow } from './MerchantsPage';
import { useResourceTable } from '../../hooks/useResourceTable';
import { useLang } from '../../i18n/LangProvider';
import { currencyFormatter, fmt, pickName, t } from '../../i18n/strings';

/** Item row as the provider returns it: an Item plus its resolved names. */
interface ItemRow extends Item {
  category_name_en: string;
  category_name_ar: string;
  category_deleted_at: string | null;
  merchant_name_en: string;
  merchant_name_ar: string;
}

/** Category row with the counts shown on each category line. */
interface CategorySummary extends Category {
  item_count: number;
  unavailable_item_count: number;
}

/**
 * Which items the list shows.
 *
 * A five-way choice, not a "show deleted" checkbox. The question behind a broken
 * menu is one of five: everything, what is in the menu, what is orderable, what
 * is sold out, or what was removed. A single boolean cannot express "the sold-out
 * ones but not the deleted ones" — which is the one that actually comes up when a
 * customer reports they cannot see an item, because the merchant will say it is
 * merely unavailable while the admin suspects it was removed.
 */
type StateFilter = 'all' | 'live' | 'available' | 'unavailable' | 'deleted';

const STATE_OPTIONS: { value: StateFilter; labelKey: Parameters<typeof t>[0] }[] = [
  { value: 'live', labelKey: 'stateLive' },
  { value: 'available', labelKey: 'stateAvailable' },
  { value: 'unavailable', labelKey: 'stateUnavailable' },
  { value: 'deleted', labelKey: 'stateDeleted' },
  { value: 'all', labelKey: 'stateAll' },
];

export function MerchantCategoriesPage({
  merchantId,
  categoryId,
}: {
  merchantId: string;
  categoryId?: string;
}) {
const { lang } = useLang();
  const { message } = App.useApp();
  const [searchParams, setSearchParams] = useSearchParams();

  const [search, setSearch] = useState('');
  const [state, setState] = useState<StateFilter>('live');
  const [addingItem, setAddingItem] = useState(false);

  // The route may carry the category explicitly or the query string may; both
  // resolve to the same selected id so a shared link and a click agree.
  const selectedId = categoryId ?? searchParams.get('category') ?? undefined;

  const currency = useMemo(() => currencyFormatter(lang), [lang]);

  const categories = useResourceTable<CategorySummary>({
    resource: 'merchant-categories',
    pagination: { current: 1, pageSize: 100 },
    meta: { merchantId },
  });

  const actions = useItemActions();

  // Not mounted until a category is chosen: fetching with an undefined category
  // would either return the whole catalog or fail, and either way the result is
  // discarded a moment later.
  const items = useResourceTable<ItemRow>({
    resource: 'category-items',
    pagination: { current: 1, pageSize: 20 },
    meta: { categoryId: selectedId ?? '', state, search },
    sorters: { initial: [{ field: 'sort_order', order: 'asc' }] },
    queryOptions: { enabled: Boolean(selectedId) },
  });

  const selected = categories.data.find((c) => c.id === selectedId);

  /**
   * The merchant this category list belongs to.
   *
   * Read from the merchant record the provider already serves, rather than
   * imported from the demo store directly: reaching into the store from a page
   * would tie the screen to the demo backend and make it unusable against the
   * live provider, which is the opposite of what the dataProvider indirection is
   * for. It is only a panel title, so it costs no extra request.
   */
  const merchant = useOne<MerchantRow>({ resource: 'merchants', id: merchantId });
  const merchantName = useMemo(() => {
    const row = merchant.data?.data;
    return row ? pickName(row.name_en, row.name_ar, lang) : null;
  }, [merchant.data, lang]);

  /**
   * Create, with the category attached here rather than inside the form.
   *
   * The form emits only the operator-editable ItemInput columns. category_id is
   * part of the ITEM, not of the input — the operator picked the category by
   * clicking it, so it is applied from that selection rather than asked for
   * again in a dropdown where a different value could be chosen by accident.
   */
  const { mutate: createItem, isLoading: isCreating } = useCreate();

  const onCreateItem = (values: ItemInput) => {
    if (!selectedId) return;
    createItem(
      { resource: 'category-items', values: { ...values, category_id: selectedId } },
      {
        onSuccess: () => {
          setAddingItem(false);
          message.success(t('itemSaved', lang));
          // Refetched rather than appended locally: the new row has to appear in
          // the state filter it belongs to, and the card header count has to
          // agree with the list.
          void items.refetch();
        },
        onError: (error: unknown) => {
          const e = error as { messageAr?: string; message?: string };
          message.error(
            (lang === 'ar' ? e.messageAr : e.message) ?? t('unexpectedError', lang),
          );
        },
      },
    );
  };

const columns: ColumnsType<ItemRow> = [
    {
      title: t('itemsTitle', lang),
      key: 'item',
      render: (_, row) => (
        <Space>
          <ItemThumb name={pickName(row.name_en, row.name_ar, lang)} />
          <Typography.Text strong>
            {pickName(row.name_en, row.name_ar, lang)}
          </Typography.Text>
        </Space>
      ),
    },
    {
      title: t('itemIdLabel', lang),
      dataIndex: 'id',
      key: 'id',
      width: 110,
      // A UUID is long and meaningless at a glance. Truncated with the full value
      // in a tooltip: an operator needs it to file a bug report, they do not
      // need to read it.
      ellipsis: true,
      render: (id: string) => (
        <Tooltip title={id}>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            {id.slice(0, 8)}
          </Typography.Text>
        </Tooltip>
      ),
    },
    {
      title: t('fieldPrice', lang),
      key: 'price',
      align: 'right',
      width: 190,
      sorter: true,
      render: (_, row) =>
        row.discount_price === null ? (
          currency(row.price)
        ) : (
          // Both prices shown when a discount is live: striking the original is
          // what makes the saving legible, and hiding the original would leave
          // only the discounted figure with nothing to compare it against.
          //
          // NOTE: no category column. This list is scoped to ONE category, which
          // the card title above and the selected row in the list beside it
          // already state. A third copy pushed the table past its container and
          // scrolled the actions column — the one column that must always be
          // reachable — out of sight.
          <Space direction="vertical" size={0} style={{ alignItems: 'flex-end' }}>
            <Typography.Text delete type="secondary" style={{ fontSize: 12 }}>
              {currency(row.price)}
            </Typography.Text>
            <Space size={4}>
              <Typography.Text strong>{currency(row.discount_price)}</Typography.Text>
              <Tag color="magenta" bordered={false}>
                {t('onPromotion', lang)}
              </Tag>
            </Space>
          </Space>
        ),
    },
    {
      title: t('colAvailability', lang),
      key: 'state',
      width: 150,
      render: (_, row) => <ItemStateTag item={row} />,
    },
    {
title: t('colActions', lang),
      key: 'actions',
      width: 210,
      fixed: 'right',
      render: (_, row) => {
        const menu: MenuProps['items'] = [
          row.deleted_at === null
            ? {
                key: 'availability',
                icon: <StopOutlined />,
                label: row.is_available
                  ? t('markUnavailable', lang)
                  : t('markAvailable', lang),
                onClick: () => actions.toggleAvailability(row.id, !row.is_available),
              }
            : {
                key: 'restore',
                icon: <UndoOutlined />,
                label: t('restoreItem', lang),
                onClick: () => actions.restore(row.id),
              },
          { type: 'divider' },
          row.deleted_at === null
            ? {
                key: 'delete',
                icon: <DeleteOutlined />,
                danger: true,
                label: t('deleteItem', lang),
                onClick: () => actions.softDelete(row),
              }
            : null,
        ].filter(Boolean) as MenuProps['items'];

        return (
          <Space size={0}>
            <Button
              type="link"
              size="small"
              icon={<EyeOutlined />}
              href={`/items/${row.id}`}
            >
              {t('viewItem', lang)}
            </Button>
            <Button
              type="link"
              size="small"
              icon={<EditOutlined />}
              href={`/items/${row.id}/edit`}
            >
              {t('editItem', lang)}
            </Button>
            <Dropdown menu={{ items: menu }} trigger={['click']}>
              <Button type="link" size="small" icon={<MoreOutlined />} aria-label={t('colActions', lang)} />
            </Dropdown>
          </Space>
        );
      },
    },
  ];

  return (
    <Flex vertical gap={16}>
      <Space wrap>
        <Button href={`/merchants/${merchantId}`} icon={<ArrowLeftOutlined />}>
          {t('backToMerchants', lang)}
        </Button>
        <Typography.Title level={4} style={{ margin: 0 }}>
          {t('categoriesTitle', lang)}
        </Typography.Title>
      </Space>

      {categories.error && (
        <Alert
          type="error"
          showIcon
          message={t('loadFailed', lang)}
          description={categories.error.message}
        />
      )}

      <Row gutter={[16, 16]} align="stretch">
        <Col xs={24} lg={7} xl={6}>
<CategoryList
            merchantName={merchantName}
            rows={categories.data}
            isLoading={categories.isLoading}
            selectedId={selectedId}
            onSelect={(id) => setSearchParams({ category: id })}
          />
        </Col>

        <Col xs={24} lg={17} xl={18}>
          {selectedId ? (
            <Card
              variant="outlined"
              title={
                <Space wrap>
                  <Typography.Text strong>
                    {selected
                      ? pickName(selected.name_en, selected.name_ar, lang)
                      : t('itemsTitle', lang)}
                  </Typography.Text>
                  <Typography.Text type="secondary" style={{ fontWeight: 400 }}>
                    {fmt(t('categoryItemsCount', lang), { n: items.total })}
                  </Typography.Text>
                </Space>
              }
              extra={
                <Space wrap>
                  <Input.Search
                    allowClear
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    placeholder={t('itemSearchPlaceholder', lang)}
                    style={{ width: 220 }}
                  />
                  <Tooltip title={t('retry', lang)}>
                    <Button
                      icon={<ReloadOutlined />}
                      onClick={() => void items.refetch()}
                    />
                  </Tooltip>
                  <Button
                    type="primary"
                    icon={<PlusOutlined />}
                    onClick={() => setAddingItem(true)}
                  >
                    {t('addItem', lang)}
                  </Button>
                </Space>
              }
            >
              <Segmented<StateFilter>
                value={state}
                onChange={setState}
                options={STATE_OPTIONS.map((o) => ({
                  value: o.value,
                  label: t(o.labelKey, lang),
                }))}
                style={{ marginBottom: 12 }}
              />

              {items.error && (
                <Alert
                  type="error"
                  showIcon
                  message={t('loadFailed', lang)}
                  description={items.error.message}
                  style={{ marginBottom: 12 }}
                />
              )}

              <Table<ItemRow>
                {...items.tableProps}
                rowKey="id"
                size="small"
                columns={columns}
                scroll={{ x: 'max-content' }}
                locale={{
                  emptyText: <Empty description={t('noData', lang)} style={{ padding: 24 }} />,
                }}
              />
            </Card>
          ) : (
            <Card variant="outlined">
              <Empty description={t('selectCategoryHint', lang)} style={{ padding: 32 }} />
            </Card>
          )}
        </Col>
      </Row>

{selectedId && (
        <ItemFormModal
          open={addingItem}
          confirmLoading={isCreating}
          onSubmit={onCreateItem}
          onCancel={() => setAddingItem(false)}
        />
      )}
    </Flex>
  );
}

/**
 * The category list.
 *
 * A List rather than a Table: each row is a navigation target with a count beside
 * it, not a grid of comparable columns. A table would imply the columns are
 * sortable, and sort_order is already fixed by whoever built the menu.
 *
 * The whole row is the target, not just its text, and it is keyboard reachable —
 * an onClick on a div alone would be neither.
 */
function CategoryList({
  merchantName,
  rows,
  isLoading,
  selectedId,
  onSelect,
}: {
  /** Shown as the panel title. The page heading above already says
   *  "Menu categories", so repeating it here would say nothing twice; naming the
   *  MERCHANT is the context this panel is actually missing. */
  merchantName: string | null;
  rows: CategorySummary[] | undefined;
  isLoading: boolean;
  selectedId: string | undefined;
  onSelect: (id: string) => void;
}) {
  const { lang } = useLang();
  const { token } = theme.useToken();

  return (
    <Card
      variant="outlined"
      title={merchantName ?? t('categoriesTitle', lang)}
      styles={{ body: { padding: rows && rows.length > 0 ? '8px 0' : 24 } }}
    >
      {isLoading ? null : !rows || rows.length === 0 ? (
        <Empty description={t('categoryEmpty', lang)} />
      ) : (
        <List
          size="small"
          dataSource={rows}
          renderItem={(category) => {
            const selected = category.id === selectedId;
            return (
              <List.Item
                onClick={() => onSelect(category.id)}
                role="button"
                tabIndex={0}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    onSelect(category.id);
                  }
                }}
                style={{
                  cursor: 'pointer',
                  paddingInline: 16,
                  // Both from the active theme. A literal tint would survive a
                  // theme change as a colour that belongs to neither — the exact
                  // failure theme/tokens.ts exists to prevent.
                  background: selected ? token.controlItemBgActive : token.colorBgContainer,
                  borderInlineStart: selected
                    ? `3px solid ${token.colorPrimaryBorder}`
                    : `3px solid ${token.colorBgContainer}`,
                }}
              >
                <Space direction="vertical" size={0} style={{ width: '100%' }}>
                  <Space>
                    <Typography.Text strong={selected}>
                      {pickName(category.name_en, category.name_ar, lang)}
                    </Typography.Text>
                    {!category.is_available && (
                      <Tag color="orange" bordered={false}>
                        {t('stateUnavailable', lang)}
                      </Tag>
                    )}
                  </Space>
                  <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                    {fmt(t('categoryItemsCount', lang), { n: category.item_count })}
                    {category.unavailable_item_count > 0
                      ? ` · ${fmt(t('categoryUnavailableCount', lang), {
                          n: category.unavailable_item_count,
                        })}`
                      : ''}
                  </Typography.Text>
                </Space>
              </List.Item>
            );
          }}
        />
      )}
    </Card>
  );
}

export { itemState };
