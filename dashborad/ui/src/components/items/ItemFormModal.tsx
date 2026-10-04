/**
 * Add / edit item, in a modal.
 *
 * The discount is the field worth explaining.
 *
 * items.discount_price has CHECK (discount_price IS NULL OR
 * (discount_price >= 0 AND discount_price <= price)) — migration 119. The form
 * therefore treats three states as genuinely different rather than as "a number
 * that might be absent":
 *
 *   empty    not on promotion
 *   0        free. Legal, and NOT the same as empty — a zero-price promo item is
 *            a real thing, and coercing it to null would silently remove it.
 *   > price  impossible. Rejected here before it reaches the provider, which
 *            rejects it again, which is what the database would do.
 *
 * WHY THE MODAL IS USED FOR CREATE BUT NOT EDIT
 *   Editing opens the item's own page, not this modal. An item has more surface
 *   than a name and a price — descriptions, options, discount, availability — and
 *   editing it is a task worth doing with the record visible beside the form.
 */
import { useEffect } from 'react';
import {
  Alert,
  Col,
  Form,
  Input,
  InputNumber,
  Modal,
  Row,
  Switch,
} from 'antd';
import type { Rule } from 'antd/es/form';
import type { Item, ItemInput } from '../../constants';
import { useLang } from '../../i18n/LangProvider';
import { fmt, t } from '../../i18n/strings';
import { useSemanticColors } from '../../theme/tokens';

export interface ItemFormModalProps {
  open: boolean;
  /** Omit for create, pass for edit. */
  item?: Item | null;
  confirmLoading?: boolean;
  errorMessage?: { en: string; ar: string } | null;
  onCancel: () => void;
  /**
   * Emits only ItemInput — the operator-editable columns.
   *
   * category_id is deliberately NOT among them: it belongs to the item, not to
   * the input, and the caller knows which category it is creating into because
   * the operator chose it. Having the form take it as a field would put a
   * dropdown in front of a decision that has already been made.
   */
  onSubmit: (values: ItemInput) => void;
}

interface FormShape extends Omit<ItemInput, 'discount_price'> {
  /** undefined = no discount, 0 = free. See the header comment. */
  discount_price?: number | null;
}

export function ItemFormModal({
  open,
  item,
  confirmLoading,
  errorMessage,
  onCancel,
  onSubmit,
}: ItemFormModalProps) {
  const { lang } = useLang();
  const colors = useSemanticColors();
  const [form] = Form.useForm<FormShape>();
  const isEdit = Boolean(item);

  const price = Form.useWatch('price', form);
  const discount = Form.useWatch('discount_price', form);

  useEffect(() => {
    if (!open) return;
    if (item) {
      form.setFieldsValue({
        name_en: item.name_en,
        name_ar: item.name_ar,
        description_en: item.description_en ?? undefined,
        description_ar: item.description_ar ?? undefined,
        price: item.price,
        discount_price: item.discount_price,
        image_url: item.image_url ?? undefined,
        is_available: item.is_available,
        sort_order: item.sort_order,
      } as Partial<FormShape>);
    } else {
      form.resetFields();
      form.setFieldsValue({
        is_available: true,
        sort_order: 0,
      } as Partial<FormShape>);
    }
  }, [open, item, form]);

  /**
   * The cross-field rule the database enforces.
   *
   * Ant Design cannot express "field B must not exceed field A" in a per-field
   * `rules` array, so it is a `dependencies` check on the price field. It runs
   * on every change of price rather than only on submit, so the error appears
   * while the operator is still looking at the price that caused it.
   */
  const priceRules: Rule[] = [
    { required: true, message: t('errRequired', lang) },
    // CHECK (price >= 0)
    { type: 'number', min: 0, message: t('errPositiveNumber', lang) },
    ({ getFieldValue }: { getFieldValue: (name: string) => unknown }) => ({
      validator(_rule: unknown, value: number | undefined) {
        const raw = getFieldValue('discount_price');
        // InputNumber can hand back an empty-string or null for a cleared field,
        // so the value is narrowed before it is compared rather than assumed to
        // be a number.
        const discount = typeof raw === 'number' ? raw : undefined;
        if (value === undefined || discount === undefined) return Promise.resolve();
        return discount <= value
          ? Promise.resolve()
          : Promise.reject(new Error(t('errDiscountAbovePrice', lang)));
      },
    }),
  ];

  const submit = (values: FormShape) => {
    onSubmit({
      ...values,
      // Normalised here so every consumer gets null rather than undefined for
      // "no discount", and 0 survives as 0.
      discount_price:
        values.discount_price === null || values.discount_price === undefined
          ? null
          : Number(values.discount_price),
      price: Number(values.price ?? 0),
    });
  };

  return (
    <Modal
      open={open}
      title={isEdit ? t('editItem', lang) : t('addItem', lang)}
      onCancel={onCancel}
      onOk={() => form.submit()}
      okText={t('save', lang)}
      cancelText={t('cancel', lang)}
      confirmLoading={confirmLoading}
      width={640}
      destroyOnClose
    >
      <Form<FormShape>
        form={form}
        layout="vertical"
        requiredMark={false}
        onFinish={submit}
        preserve
      >
        {errorMessage && (
          <Alert
            type="error"
            showIcon
            style={{ marginBottom: 16 }}
            message={lang === 'ar' ? errorMessage.ar : errorMessage.en}
          />
        )}

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item
              name="name_en"
              label={t('fieldNameEn', lang)}
              rules={[{ required: true, message: t('errRequired', lang) }]}
            >
              <Input />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Form.Item
              name="name_ar"
              label={t('fieldNameAr', lang)}
              rules={[{ required: true, message: t('errRequired', lang) }]}
            >
              <Input dir="rtl" />
            </Form.Item>
          </Col>
        </Row>

        <Form.Item name="description_en" label={t('fieldDescriptionEn', lang)}>
          <Input.TextArea rows={2} />
        </Form.Item>
        <Form.Item name="description_ar" label={t('fieldDescriptionAr', lang)}>
          <Input.TextArea rows={2} dir="rtl" />
        </Form.Item>

        <Row gutter={16}>
          <Col xs={12} md={8}>
            <Form.Item
              name="price"
              label={t('fieldPrice', lang)}
              rules={priceRules}
              dependencies={['discount_price']}
            >
              <InputNumber style={{ width: '100%' }} min={0} step={1} />
            </Form.Item>
          </Col>
          <Col xs={12} md={8}>
            <Form.Item
              name="discount_price"
              label={t('fieldDiscountPrice', lang)}
              extra={t('discountHint', lang)}
            >
              <InputNumber style={{ width: '100%' }} min={0} step={1} placeholder="—" />
            </Form.Item>
          </Col>
          <Col xs={12} md={8}>
            <Form.Item
              name="sort_order"
              label={t('colSortOrder', lang)}
              rules={[{ type: 'number', min: 0, message: t('errPositiveNumber', lang) }]}
            >
              <InputNumber style={{ width: '100%' }} min={0} />
            </Form.Item>
          </Col>
        </Row>

        {/* Live read-out of the saving, so the discount is understood as a
            percentage rather than just a smaller number. Recomputed here instead
            of stored: a stored percentage would go stale the moment the price
            changed. */}
        {typeof price === 'number' &&
          price > 0 &&
          typeof discount === 'number' &&
          discount <= price &&
          discount < price && (
            <Alert
              type="info"
              showIcon
              style={{ marginBottom: 16, background: colors.colorNeutralSoft, border: 'none' }}
              message={fmt(t('discountPercent', lang), {
                n: Math.round(((price - discount) / price) * 100),
              })}
            />
          )}

        <Form.Item
          name="is_available"
          label={t('colAvailability', lang)}
          valuePropName="checked"
          extra={t('itemStateUnavailableHint', lang)}
        >
          <Switch />
        </Form.Item>

        <Form.Item name="image_url" label={t('fieldImageUrl', lang)}>
          <Input placeholder="—" />
        </Form.Item>
      </Form>
    </Modal>
  );
}