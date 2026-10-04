/**
 * Item detail — the read-only view.
 *
 * Shows the item the way a customer would meet it (name, price, what it is
 * currently on offer at) alongside the administrative facts (state, category,
 * order placement, IDs) that only the dashboard cares about.
 *
 * The state block is given the most prominence of anything that is not the name.
 * An item can be in three different states and the wrong one costs money in both
 * directions — a deleted item still showing a price looks sellable, and an
 * unavailable item showing no price looks removed. So the price and the state are
 * stated together, in that order, every time.
 */
import { useMemo } from 'react';
import { useOne } from '@refinedev/core';
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
import { ArrowLeftOutlined, EditOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router';
import type { Item, ItemOptionWithChoices } from '../../constants';
import { ItemStateTag } from '../../components/items/ItemStateTag';
import { ItemThumb } from '../../components/common/ItemThumb';
import { useLang, useNumberLocale } from '../../i18n/LangProvider';
import { currencyFormatter, errorText, fmt, pickName, t } from '../../i18n/strings';

interface ItemRow extends Item {
  category_name_en: string;
  category_name_ar: string;
  category_deleted_at: string | null;
  merchant_name_en: string;
  merchant_name_ar: string;
}

interface ItemDetail extends ItemRow {
  options: ItemOptionWithChoices[];
}

export function ItemViewPage({ itemId }: { itemId: string }) {
  const { lang } = useLang();
  const locale = useNumberLocale();
  const navigate = useNavigate();

  /**
 * useOne returns a WRAPPED record: its `data` is `{ data: T }`, not `T`.
 *
 * Unwrapped once here into `record` so the rest of the file can treat it as a
 * plain object. Doing the `.data` at each use site would be both noisier and an
 * easy place to get subtly wrong.
 */
const { data: response, isLoading, error } = useOne<ItemDetail>({
  resource: 'items',
  id: itemId,
});
const item = response?.data;

  const currency = useMemo(() => currencyFormatter(lang), [lang]);
  const dateFormat = useMemo(
    () => new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeStyle: 'short' }),
    [locale],
  );

  if (isLoading) {
    return (
      <Card variant="outlined">
        <Spin />
      </Card>
    );
  }

  if (error || !item) {
    return (
      <Alert
        type="error"
        showIcon
        message={t('itemNotFound', lang)}
        description={errorText(error, lang)}
      />
    );
  }

  // Narrowed once: `onPromotion` is a boolean, so TypeScript cannot carry the
// null-check on discount_price through it. Binding the value does.
const { discount_price: discount } = item;
const onPromotion = discount !== null && discount !== undefined;
  const categoryGone = item.category_deleted_at !== null;

  return (
    <Flex vertical gap={16}>
      <Flex align="center" justify="space-between" wrap gap={12}>
        <Space wrap>
          {/* Goes back to wherever this item is listed from. An item is reached
              from its category, so the category is the meaningful parent —
              "back to merchants" would dump the operator two levels up and lose
              the context that explains why they are looking at this item. */}
          <Button
            onClick={() =>
              navigate(
                `/merchants/${item.merchant_id}/categories/${item.category_id}`,
                { replace: true },
              )
            }
            icon={<ArrowLeftOutlined />}
          >
            {t('backToItems', lang)}
          </Button>
          <ItemThumb name={pickName(item.name_en, item.name_ar, lang)} size={44} />
          <Typography.Title level={4} style={{ margin: 0 }}>
            {pickName(item.name_en, item.name_ar, lang)}
          </Typography.Title>
          <ItemStateTag item={item} />
        </Space>

        <Space>
          <Button
            type="primary"
            icon={<EditOutlined />}
            href={`/items/${item.id}/edit`}
          >
            {t('editItem', lang)}
          </Button>
        </Space>
      </Flex>

      {/* Two states worth stating in words rather than only as a tag, because
          both are actionable and both are the reason an operator ends up on this
          page: a deleted item needs restoring, an unavailable one needs the
          merchant to restock it. */}
      {item.deleted_at !== null && (
        <Alert
          type="error"
          showIcon
          message={t('itemStateDeleted', lang)}
          description={t('itemStateDeletedHint', lang)}
        />
      )}
      {item.deleted_at === null && !item.is_available && (
        <Alert
          type="warning"
          showIcon
          message={t('itemStateUnavailable', lang)}
          description={t('itemStateUnavailableHint', lang)}
        />
      )}
      {categoryGone && (
        <Alert
          type="warning"
          showIcon
          message={t('stateDeleted', lang)}
          // A live item inside a deleted category is a genuine inconsistency:
          // migration 110 says soft-deleting a category hides it and its items,
          // so the item is not orderable even though nothing about the ITEM says
          // so. Saying it here prevents a support question with no answer.
          description={t('categoryEmpty', lang)}
        />
      )}

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={14}>
          <Card title={t('itemsTitle', lang)} variant="outlined">
            <Space direction="vertical" size={12} style={{ width: '100%' }}>
              <Space align="baseline" size={12} wrap>
                {onPromotion && discount !== null && discount !== undefined ? (
                  <>
                    <Typography.Text delete type="secondary">
                      {currency(item.price)}
                    </Typography.Text>
                    <Typography.Title level={3} style={{ margin: 0 }}>
                      {currency(discount)}
                    </Typography.Title>
                    <Tag color="magenta">{t('onPromotion', lang)}</Tag>
                    <Typography.Text type="secondary">
                      {fmt(t('discountPercent', lang), {
                        n: Math.round(((item.price - discount) / item.price) * 100),
                      })}
                    </Typography.Text>
                  </>
                ) : (
                  <Typography.Title level={3} style={{ margin: 0 }}>
                    {currency(item.price)}
                  </Typography.Title>
                )}
              </Space>

              {(item.description_en || item.description_ar) && (
                <Space direction="vertical" size={2}>
                  {item.description_en && <Typography.Text>{item.description_en}</Typography.Text>}
                  {item.description_ar && (
                    <Typography.Text type="secondary" dir="rtl">
                      {item.description_ar}
                    </Typography.Text>
                  )}
                </Space>
              )}
            </Space>
          </Card>

          <div style={{ height: 16 }} />

          <Card title={t('optionsTitle', lang)} variant="outlined">
            <Typography.Paragraph type="secondary" style={{ fontSize: 12 }}>
              {t('optionsHint', lang)}
            </Typography.Paragraph>

            {item.options.length === 0 ? (
              <Empty description={t('optionsEmpty', lang)} />
            ) : (
              <Flex vertical gap={16}>
                {item.options.map((group) => (
                  <div key={group.id}>
                    <Space style={{ marginBottom: 6 }} wrap>
                      <Typography.Text strong>
                        {pickName(group.name_en, group.name_ar, lang)}
                      </Typography.Text>
                      <Tag bordered={false} color={group.is_required ? 'blue' : 'default'}>
                        {group.is_required ? t('optionRequired', lang) : t('optionOptional', lang)}
                      </Tag>
                      {/* The selection bounds are the part that gets misread. A
                          group marked "required" with max 1 reads as "the
                          customer must pick one"; a group with min 0 and no max
                          means "any number, including none". */}
                      <Tooltip
                        title={
                          group.max_selections === null
                            ? t('optionOptional', lang)
                            : `${group.min_selections}–${group.max_selections}`
                        }
                      >
                        <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                          {group.max_selections === null
                            ? '∞'
                            : `${group.min_selections}–${group.max_selections}`}
                        </Typography.Text>
                      </Tooltip>
                    </Space>

                    <List
                      size="small"
                      dataSource={group.choices}
                      renderItem={(choice) => (
                        <List.Item
                          style={
                            // Sold-out choices are dimmed rather than hidden: the
                            // customer still sees them, so an operator debugging
                            // a menu needs to see them too.
                            choice.is_available ? undefined : { opacity: 0.55 }
                          }
                        >
                          <List.Item.Meta
                            avatar={
                              choice.is_default ? (
                                <Tag bordered={false} color="green">
                                  {t('optionDefault', lang)}
                                </Tag>
                              ) : undefined
                            }
                            title={pickName(choice.name_en, choice.name_ar, lang)}
                            description={
                              // Absent for most choices: the column is nullable
                              // and largely unpopulated, so nothing is rendered
                              // rather than a placeholder implying a recorded 0.
                              choice.calories === null
                                ? undefined
                                : fmt(t('calories', lang), { n: choice.calories })
                            }
                          />
                          <Space>
                            {!choice.is_available && (
                              <Tag color="orange" bordered={false}>
                                {t('optionSoldOut', lang)}
                              </Tag>
                            )}
                            <Typography.Text
                              type={choice.price_modifier === 0 ? 'secondary' : undefined}
                              style={
                                choice.price_modifier === 0 ? { fontSize: 12 } : undefined
                              }
                            >
                              {/* The modifier is signed: a negative one is a
                                  reduction, and rendering it without its sign
                                  would turn a discount into a surcharge. */}
                              {choice.price_modifier > 0 ? '+' : ''}
                              {currency(choice.price_modifier)}
                            </Typography.Text>
                          </Space>
                        </List.Item>
                      )}
                    />
                  </div>
                ))}
              </Flex>
            )}
          </Card>
        </Col>

        <Col xs={24} lg={10}>
          <Card title={t('merchantDetails', lang)} variant="outlined">
            <Descriptions
              size="small"
              column={1}
              items={[
                {
                  key: 'id',
                  label: t('itemIdLabel', lang),
                  children: (
                    <Typography.Text copyable={{ text: item.id }} style={{ fontSize: 12 }}>
                      {item.id}
                    </Typography.Text>
                  ),
                },
                {
                  key: 'merchant',
                  label: t('merchantsTitle', lang),
                  children: (
                    <Button type="link" size="small" href={`/merchants/${item.merchant_id}`}>
                      {pickName(item.merchant_name_en, item.merchant_name_ar, lang)}
                    </Button>
                  ),
                },
                {
                  key: 'category',
                  label: t('colCategory', lang),
                  children: (
                    <Button
                      type="link"
                      size="small"
                      href={`/merchants/${item.merchant_id}/categories/${item.category_id}`}
                    >
                      {pickName(item.category_name_en, item.category_name_ar, lang)}
                    </Button>
                  ),
                },
                {
                  key: 'order',
                  label: t('colPosition', lang),
                  children: String(item.sort_order),
                },
                {
                  key: 'popularity',
                  label: t('popularityScore', lang),
                  children: String(item.popularity_score),
                },
                {
                  key: 'created',
                  label: t('merchantCreated', lang),
                  children: dateFormat.format(new Date(item.created_at)),
                },
                {
                  key: 'updated',
                  label: t('lastUpdated', lang),
                  children: dateFormat.format(new Date(item.updated_at)),
                },
                {
                  key: 'deleted',
                  label: t('stateDeleted', lang),
                  // Null means never deleted. An em dash is ambiguous — it reads
                  // as "no value" — so the state is named.
                  children: item.deleted_at
                    ? dateFormat.format(new Date(item.deleted_at))
                    : t('neverDeleted', lang),
                },
              ]}
            />
          </Card>
        </Col>
      </Row>
    </Flex>
  );
}