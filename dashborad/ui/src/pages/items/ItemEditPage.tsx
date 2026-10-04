/**
 * Item edit — a page, not a modal.
 *
 * WHY A PAGE
 *   Editing an item is a longer task than creating one: the record is worth
 *   reading first (its price, its discount, its options) and the operator is
 *   usually reacting to something a customer reported. The options list stays
 *   visible beside the form so an edit to the price can be checked against the
 *   choice modifiers that sit on top of it.
 *
 * WHY OPTIONS ARE READ-ONLY HERE
 *   option groups are configuration with real constraints of their own —
 *   item_options has CHECK (min_selections <= max_selections) and
 *   CHECK (is_required => min_selections >= 1), and migration 111 adds a trigger
 *   rejecting a default choice that is unavailable. That is a separate piece of
 *   work with its own failure modes, and half-implementing it in the same pass
 *   as the item form would put a screen in front of an operator that could
 *   corrupt the option table. It is shown read-only, and labelled as such, rather
 *   than silently omitted.
 *
 * The save goes through the same ItemFormModal fields, so the validation rules —
 * including the discount <= price check the database enforces — are identical
 * between create and edit. Duplicating them here would guarantee they drift.
 */
import { useMemo, useState } from 'react';
import { useOne, useUpdate } from '@refinedev/core';
import {
  Alert,
  App,
  Button,
  Card,
  Col,
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
import { ArrowLeftOutlined, DeleteOutlined, UndoOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router';
import type { Item, ItemInput, ItemOptionWithChoices } from '../../constants';
import { ItemStateTag } from '../../components/items/ItemStateTag';
import { ItemThumb } from '../../components/common/ItemThumb';
import { ItemFormModal } from '../../components/items/ItemFormModal';
import { useItemActions } from '../../hooks/useItemActions';
import { useLang } from '../../i18n/LangProvider';
import { currencyFormatter, errorText, pickName, t } from '../../i18n/strings';

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

export function ItemEditPage({ itemId }: { itemId: string }) {
  const { lang } = useLang();
  const { message } = App.useApp();
  const navigate = useNavigate();
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<{ en: string; ar: string } | null>(null);

  /** useOne wraps the record: `data` is `{ data: T }`. Unwrapped once, here. */
const { data: response, isLoading, error } = useOne<ItemDetail>({
  resource: 'items',
  id: itemId,
});
const item = response?.data;
  const { mutate: updateItem } = useUpdate<ItemInput>();
  const actions = useItemActions();

  const currency = useMemo(() => currencyFormatter(lang), [lang]);

  const backTo = (item: ItemRow) =>
    `/merchants/${item.merchant_id}/categories/${item.category_id}`;

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

  const onSubmit = (values: ItemInput) => {
    setSaving(true);
    setFormError(null);
    updateItem(
      { resource: 'items', id: item.id, values },
      {
        onSuccess: () => {
          setSaving(false);
          message.success(t('itemSaved', lang));
          // Back to the list rather than staying here: the operator's task is
          // done, and the list is where they verify it and pick the next item.
          navigate(backTo(item), { replace: true });
        },
        onError: (updateError: unknown) => {
          setSaving(false);
          const e = updateError as { messageAr?: string; message?: string };
          setFormError({ en: e.message ?? '', ar: e.messageAr ?? e.message ?? '' });
        },
      },
    );
  };

  return (
    <Flex vertical gap={16}>
      <Flex align="center" justify="space-between" wrap gap={12}>
        <Space wrap>
          <Button onClick={() => navigate(backTo(item))} icon={<ArrowLeftOutlined />}>
            {t('backToItems', lang)}
          </Button>
          <ItemThumb name={pickName(item.name_en, item.name_ar, lang)} size={40} />
          <Typography.Title level={4} style={{ margin: 0 }}>
            {pickName(item.name_en, item.name_ar, lang)}
          </Typography.Title>
          <ItemStateTag item={item} />
        </Space>

        {/* Delete and restore live on the edit screen as well as in the list.
            An operator who has opened an item to fix a problem is the one most
            likely to conclude it should come out of the menu entirely, and
            making them go back to a list to do it is how a sold-out item stays
            listed for another week. */}
        <Space>
          {item.deleted_at === null ? (
            <Button
              danger
              icon={<DeleteOutlined />}
              onClick={() => actions.softDelete(item)}
            >
              {t('deleteItem', lang)}
            </Button>
          ) : (
            <Button icon={<UndoOutlined />} onClick={() => actions.restore(item.id)}>
              {t('restoreItem', lang)}
            </Button>
          )}
        </Space>
      </Flex>

      <Row gutter={[16, 16]}>
        <Col xs={24} xl={14}>
          <ItemFormModal
            // Open immediately and without a trigger: this IS the edit screen, so
            // a modal that has to be opened reads as a dialog on top of a page
            // that should not have existed.
            open
            item={item}
            confirmLoading={saving}
            errorMessage={formError}
            onCancel={() => navigate(backTo(item), { replace: true })}
            onSubmit={onSubmit}
          />
        </Col>

        <Col xs={24} xl={10}>
          <Card
            title={t('optionsTitle', lang)}
            variant="outlined"
            extra={
              <Tag bordered={false}>{t('optionsReadOnly', lang)}</Tag>
            }
          >
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
                    </Space>

                    <List
                      size="small"
                      dataSource={group.choices}
                      renderItem={(choice) => (
                        <List.Item
                          style={choice.is_available ? undefined : { opacity: 0.55 }}
                        >
                          <List.Item.Meta
                            title={pickName(choice.name_en, choice.name_ar, lang)}
                          />
                          <Space>
                            {choice.is_default && (
                              <Tag bordered={false} color="green">
                                {t('optionDefault', lang)}
                              </Tag>
                            )}
                            {!choice.is_available && (
                              <Tag color="orange" bordered={false}>
                                {t('optionSoldOut', lang)}
                              </Tag>
                            )}
                            <Tooltip title={t('optionPriceModifier', lang)}>
                              <Typography.Text
                                type={choice.price_modifier === 0 ? 'secondary' : undefined}
                                style={
                                  choice.price_modifier === 0 ? { fontSize: 12 } : undefined
                                }
                              >
                                {choice.price_modifier > 0 ? '+' : ''}
                                {currency(choice.price_modifier)}
                              </Typography.Text>
                            </Tooltip>
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
      </Row>
    </Flex>
  );
}