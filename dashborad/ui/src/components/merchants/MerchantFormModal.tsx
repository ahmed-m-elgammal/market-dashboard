/**
 * Add / edit merchant form, in a modal.
 *
 * Field selection is the interesting part. MerchantInput in constants.ts lists
 * exactly the operator-editable columns, and this form covers all of them and
 * nothing else. Deliberately absent:
 *
 *   id                 assigned by the database
 *   rating, rating_count  a customer-facing aggregate. A form field here would
 *                        let an admin invent a 5.0 for a vendor nobody has
 *                        ordered from yet.
 *   approval_status    set by the review process, not by the person creating the
 *                      listing — a new merchant arrives 'pending' regardless of
 *                      what this form sends (see store.createMerchant).
 *   is_active          a runtime kill-switch, an operations action rather than
 *                      part of describing the business.
 *
 * Both name fields are required rather than one falling back to the other: the
 * database stores name_ar / name_en as separate NOT NULL columns, so a merchant
 * with only one would render blank for half the users. pickName() tolerates a
 * missing name at READ time, but there is no reason to create one.
 */
import { useEffect, useRef, useState } from 'react';
import { Alert, Col, Form, Input, InputNumber, Modal, Row, Select, Typography } from 'antd';
import type { Rule } from 'antd/es/form';
import {
  PAYOUT_FREQUENCIES,
  PAYOUT_METHODS,
  type Merchant,
  type MerchantInput,
} from '../../constants';
import { MERCHANT_CATEGORY_META } from '../../demo/merchantCategories';
import { useLang } from '../../i18n/LangProvider';
import { pickName, t, tStatus, type StringKey } from '../../i18n/strings';
import {
  tryParseGoogleMapsLink,
  type MapsLinkParseError,
  type ParseFailure,
} from '../../lib/mapsLink';
import { parsePastedPlace } from '../../lib/pastedPlace';
import { useSemanticColors } from '../../theme/tokens';

/** Lookup rows are needed for both languages, so the whole array is passed in. */
type CategoryMeta = { code: string; name_en: string; name_ar: string };

/**
 * Message key for each parse failure.
 *
 * `empty` is deliberately absent — an empty box is not an error, it is the field
 * being unused. Returning null makes the caller show nothing.
 */
const MAPS_FAILURE_KEY: Partial<Record<ParseFailure, StringKey>> = {
  short_link: 'mapsLinkShortLink',
  no_coordinates: 'mapsLinkNoCoordinates',
  not_google_maps: 'mapsLinkNotMaps',
  not_a_url: 'mapsLinkInvalid',
};

/**
 * Does this name read as Arabic?
 *
 * Google's slug carries whichever name the place is listed under, which for an
 * Egyptian listing is usually the Arabic one. Both name columns are NOT NULL, so
 * a hint is only ever a prefill for ONE of them and the other still has to be
 * typed — this decides which column the hint belongs in.
 *
 * Any Arabic letter counts. Checking for the whole block would be stricter, but
 * a name like "Cafe南京" or "Pizza 5 نجوم" mixes scripts and the Arabic letter
 * is the part that must go in the Arabic column.
 */
function looksArabic(s: string): boolean {
  return /\p{Script=Arabic}/u.test(s);
}

/**
 * Per-field rules, declared once and referenced by each Form.Item.
 *
 * `Rule` rather than FormProps['rules'] because rules live on Form.Item, not on
 * Form — the Form component itself takes no `rules` prop.
 */
type Rules = Partial<Record<keyof MerchantInput, Rule[]>>;

export interface MerchantFormProps {
  open: boolean;
  /** Omit for create, pass for edit. */
  merchant?: Merchant | null;
  /** Fields the database rejects; bilingual so the message follows the UI. */
  errorMessage?: { en: string; ar: string } | null;
  confirmLoading?: boolean;
  onCancel: () => void;
  onSubmit: (values: MerchantInput) => void;
  categories?: CategoryMeta[];
}

export function MerchantFormModal({
  open,
  merchant,
  errorMessage,
  confirmLoading,
  onCancel,
  onSubmit,
  categories = MERCHANT_CATEGORY_META,
}: MerchantFormProps) {
  const { lang } = useLang();
  const colors = useSemanticColors();
  const [form] = Form.useForm<MerchantInput>();
  const isEdit = Boolean(merchant);

  // Feedback for the Maps helper, kept out of the form because it is not a
  // column: null means "nothing said yet". A failure carries the key so the
  // message follows the UI language at render time rather than at parse time.
  const [mapsNote, setMapsNote] = useState<{ ok: true } | { ok: false; key: StringKey } | null>(
    null,
  );

  // Same idea for the address/phone paste. `filled` distinguishes "recognised
  // something" from "found nothing", because the second is the case that needs
  // the operator to try a different selection in Maps.
  const [pasteNote, setPasteNote] = useState<'filled' | 'nothing' | null>(null);

  /**
   * Fields a helper filled, so a LATER paste can replace them.
   *
   * The rule is not "never overwrite" — it is "never overwrite what the operator
   * typed". Tracking which fields came from the scraper is what separates the
   * two, and without it the second paste was silently ignored: the first link's
   * coordinates were still sitting in the fields, so they counted as non-empty,
   * and pasting a different restaurant changed nothing at all.
   */
  const autoFilled = useRef<Set<string>>(new Set());

  /**
   * Stage a field's value if the operator has not typed over it.
   *
   * Fills when the field is empty, or when we were the ones who filled it last
   * time. Refuses when the operator has since typed their own value — a
   * corrected name or a hand-moved pin is not theirs to lose because someone
   * pasted a second link.
   */
  const claim = (patch: Record<string, unknown>, key: keyof MerchantInput, value: string | number) => {
    const current = form.getFieldValue(key);
    const isEmpty = current === undefined || current === null || current === '';
    if (!isEmpty && !autoFilled.current.has(key)) return false;

    patch[key] = value;
    autoFilled.current.add(key);
    return true;
  };

  /**
   * Fill fields from a pasted Maps link.
   *
   * Replaces anything this helper filled before, and leaves anything the
   * operator typed alone.
   */
  /**
   * Drop a field from autoFilled the moment the operator edits it.
   *
   * AntD's `onValuesChange` fires ONLY for user edits — `setFieldsValue` does
   * not trigger it. That makes it the exact discriminator needed here: anything
   * it reports was typed by a person, so a later paste must leave it alone.
   *
   * The earlier attempt tracked this by comparing values, which failed: a paste
   * left the field non-empty, the set still said "ours", and pasting a third
   * link overwrote a latitude the operator had deliberately retyped.
   */
  const onUserEdit = (changed: Partial<MerchantInput>) => {
    for (const key of Object.keys(changed)) autoFilled.current.delete(key);
  };

  const applyMapsLink = (raw: string) => {
    const result = tryParseGoogleMapsLink(raw);

    if (!result.ok) {
      const code = (result.error as MapsLinkParseError).code;
      const key = MAPS_FAILURE_KEY[code];
      setMapsNote(key ? { ok: false, key } : null);
      return;
    }

    const { lat, lng, nameHint } = result.value;
    const patch: Record<string, unknown> = {};

    claim(patch, 'lat', lat);
    claim(patch, 'lng', lng);

    // One hint, one column. Which column depends on the script the name is in;
    // the other name stays empty and required, because both columns are NOT NULL.
    if (nameHint) {
      if (looksArabic(nameHint)) claim(patch, 'name_ar', nameHint);
      else claim(patch, 'name_en', nameHint);
    }

    if (Object.keys(patch).length > 0) form.setFieldsValue(patch);
    setMapsNote({ ok: true });
  };

  /**
   * Fill address and phone from text copied out of the Maps info panel.
   *
   * Same claim rule as the link helper: replaces its own earlier fill, never the
   * operator's.
   */
  const applyPastedPlace = (raw: string) => {
    const { phone, address } = parsePastedPlace(raw);
    const patch: Record<string, unknown> = {};

    if (address) claim(patch, 'address', address);
    if (phone) claim(patch, 'phone', phone);

    if (Object.keys(patch).length > 0) {
      form.setFieldsValue(patch);
      setPasteNote('filled');
    } else {
      // Either nothing was recognised, or every field it did recognise already
      // held something the operator typed. Both need them to look again.
      setPasteNote('nothing');
    }
  };

  const clearMapsNote = () => setMapsNote(null);

  // Refill when the modal opens on a different merchant. Keyed on the id rather
  // than on `open`, so re-opening the SAME merchant does not clear a
  // half-typed form.
  useEffect(() => {
    if (!open) return;
    clearMapsNote();
    setPasteNote(null);
    // Values already in the form belong to the operator, not to us. Forgetting
    // this set is what would let a helper overwrite a field someone typed into
    // before opening the modal.
    autoFilled.current = new Set();
    if (merchant) {
      form.setFieldsValue({
        name_en: merchant.name_en,
        name_ar: merchant.name_ar,
        category: merchant.category,
        description_en: merchant.description_en ?? undefined,
        description_ar: merchant.description_ar ?? undefined,
        address: merchant.address,
        city: merchant.city,
        area: merchant.area ?? undefined,
        phone: merchant.phone,
        min_order_amount: merchant.min_order_amount,
        estimated_delivery_minutes: merchant.estimated_delivery_minutes,
        estimated_prep_time_minutes: merchant.estimated_prep_time_minutes,
        delivery_fee_override: merchant.delivery_fee_override ?? undefined,
        commission_pct: merchant.commission_pct ?? undefined,
        delivery_radius_km: merchant.delivery_radius_km,
        payout_frequency: merchant.payout_frequency,
        payout_method: merchant.payout_method,
        wallet_phone: merchant.wallet_phone ?? undefined,
        // Required columns, so they have to be seeded on edit too. Without them
        // the fields render blank for an existing merchant and the now-required
        // rules reject a save that changed nothing but the phone number.
        lat: merchant.lat,
        lng: merchant.lng,
      });
    } else {
      form.resetFields();
      // Sensible starting values so the form is not a wall of empty required
      // fields. These match the schema defaults, so leaving them alone produces
      // the same row the database would have.
      form.setFieldsValue({
        category: 'restaurant',
        min_order_amount: 0,
        estimated_delivery_minutes: 30,
        estimated_prep_time_minutes: 30,
        delivery_radius_km: 10,
        payout_frequency: 'weekly',
        payout_method: 'bank_transfer',
      } as Partial<MerchantInput>);
    }
  }, [open, merchant, form]);

  /**
 * Per-field rules, declared once and referenced by each Form.Item.
 *
 * `Rule` rather than FormProps['rules'] because rules live on Form.Item, not on
 * Form — the Form component itself takes no `rules` prop.
 */
const rules: Rules = {
  name_en: [{ required: true, message: t('errRequired', lang) }],
  name_ar: [{ required: true, message: t('errRequired', lang) }],
  category: [{ required: true, message: t('errRequired', lang) }],
  address: [{ required: true, message: t('errRequired', lang) }],
  city: [{ required: true, message: t('errRequired', lang) }],
  phone: [
    { required: true, message: t('errRequired', lang) },
    // Deliberately loose. The column is text with no format constraint, and a
    // stricter rule would reject numbers that are valid in Egypt (landlines with
    // an area code, numbers with a leading 0, +20 with or without a space) to
    // enforce a convention the database never required.
    { pattern: /^[+0-9][0-9\s-]{5,}$/, message: t('errPhone', lang) },
  ],
  // Both are NOT NULL in the database, so "not typed" must fail here rather than
  // as a 400 from the API. The bounds mirror the table's CHECK constraints, so
  // the form cannot produce a row the database would reject.
  //
  // `type` and `min`/`max` are in ONE rule object on purpose. Split across two
  // objects, async-validator types the bounds rule from the value alone, treats
  // 31.1198217 as a string, and then compares it to -90 — so a valid coordinate
  // was rejected with "enter a valid number" while sitting in the field looking
  // correct. Verified in the browser before and after.
  lat: [
    { required: true, message: t('errRequired', lang) },
    { type: 'number', min: -90, max: 90, message: t('errInvalidNumber', lang) },
  ],
  lng: [
    { required: true, message: t('errRequired', lang) },
    { type: 'number', min: -180, max: 180, message: t('errInvalidNumber', lang) },
  ],
  // CHECK (min_order_amount >= 0)
  min_order_amount: [{ type: 'number', min: 0, message: t('errPositiveNumber', lang) }],
  // CHECK (estimated_delivery_minutes > 0)
  estimated_delivery_minutes: [{ type: 'number', min: 1, message: t('errPositiveNumber', lang) }],
  estimated_prep_time_minutes: [
    { type: 'number', min: 1, message: t('errPositiveNumber', lang) },
  ],
  // CHECK (delivery_radius_km > 0)
  delivery_radius_km: [{ type: 'number', min: 1, message: t('errPositiveNumber', lang) }],
  // CHECK (commission_pct IS NULL OR 0..100)
  commission_pct: [{ type: 'number', min: 0, max: 100, message: t('errPositiveNumber', lang) }],
};

  return (
    <Modal
      open={open}
      title={isEdit ? t('editMerchant', lang) : t('createMerchant', lang)}
      onCancel={onCancel}
      okText={isEdit ? t('save', lang) : t('createMerchant', lang)}
      cancelText={t('cancel', lang)}
      confirmLoading={confirmLoading}
      width={720}
      destroyOnClose
      onOk={() => form.submit()}
    >
      <Form<MerchantInput>
        form={form}
        layout="vertical"
        requiredMark={false}
        onFinish={onSubmit}
        onValuesChange={onUserEdit}
        // Preserves what was typed when a submit fails validation. Without this
        // the fields reset and the operator retypes the whole merchant.
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

        {/*
          Maps helper. Deliberately NOT a Form.Item: `maps_link` is not a column,
          so a named item would submit an unknown key. Plain markup inside the
          Form is fine — Form only collects what it finds in named items.
        */}
        <div style={{ marginBottom: 16 }}>
          <Typography.Text strong>{t('fieldMapsLink', lang)}</Typography.Text>
          <Input
            placeholder="https://maps.app.goo.gl/…"
            onChange={(e) => {
              const v = e.target.value;
              if (v.trim() === '') {
                clearMapsNote();
                return;
              }
              applyMapsLink(v);
            }}
            style={{ marginTop: 4 }}
          />
          <Typography.Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 4 }}>
            {t('mapsLinkHint', lang)}
          </Typography.Text>
          {mapsNote && (
            <Typography.Text
              type={mapsNote.ok ? 'success' : 'warning'}
              style={{ fontSize: 12, display: 'block', marginTop: 4 }}
            >
              {mapsNote.ok ? t('mapsLinkFilled', lang) : t(mapsNote.key, lang)}
            </Typography.Text>
          )}
        </div>

        {/*
          Address and phone are not in the link — Google loads them after the
          page's JavaScript runs, and no free dataset carries them (verified:
          no tel: link, no OSM extratags, zero phones within 60m of the test
          place). So the operator pastes the two lines Maps shows instead, and
          this reads them. Faster than typing, no API, no cost.
        */}
        <div style={{ marginBottom: 16 }}>
          <Typography.Text strong>{t('fieldMapsPaste', lang)}</Typography.Text>
          <Input.TextArea
            rows={2}
            onChange={(e) => {
              const v = e.target.value;
              if (v.trim() === '') {
                setPasteNote(null);
                return;
              }
              applyPastedPlace(v);
            }}
            style={{ marginTop: 4 }}
          />
          <Typography.Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 4 }}>
            {t('mapsPasteHint', lang)}
          </Typography.Text>
          {pasteNote && (
            <Typography.Text
              type={pasteNote === 'filled' ? 'success' : 'warning'}
              style={{ fontSize: 12, display: 'block', marginTop: 4 }}
            >
              {pasteNote === 'filled' ? t('mapsPasteFilled', lang) : t('mapsPasteNothing', lang)}
            </Typography.Text>
          )}
        </div>

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item
              name="name_en"
              label={t('fieldNameEn', lang)}
              rules={rules.name_en}
            >
              <Input />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Form.Item name="name_ar" label={t('fieldNameAr', lang)} rules={rules.name_ar}>
              <Input dir="rtl" />
            </Form.Item>
          </Col>
        </Row>

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item
              name="category"
              label={t('fieldCategory', lang)}
              rules={rules.category}
              extra={
                // The eight codes are a closed set (migration 097, FK in 098),
                // so this list cannot offer a value the database would reject.
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                  {categories.length}
                </Typography.Text>
              }
            >
              <Select
                options={categories.map((c) => ({
                  value: c.code,
                  label: pickName(c.name_en, c.name_ar, lang),
                }))}
              />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Form.Item name="phone" label={t('fieldPhone', lang)} rules={rules.phone}>
              <Input />
            </Form.Item>
          </Col>
        </Row>

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item name="address" label={t('fieldAddress', lang)} rules={rules.address}>
              <Input />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Row gutter={12}>
              <Col span={12}>
                <Form.Item name="city" label={t('fieldCity', lang)} rules={rules.city}>
                  <Input />
                </Form.Item>
              </Col>
              <Col span={12}>
                <Form.Item name="area" label={t('fieldArea', lang)}>
                  <Input />
                </Form.Item>
              </Col>
            </Row>
          </Col>
        </Row>

        <Form.Item name="description_en" label={t('fieldDescriptionEn', lang)}>
          <Input.TextArea rows={2} />
        </Form.Item>
        <Form.Item name="description_ar" label={t('fieldDescriptionAr', lang)}>
          <Input.TextArea rows={2} dir="rtl" />
        </Form.Item>

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item
              name="min_order_amount"
              label={t('fieldMinOrder', lang)}
              rules={rules.min_order_amount}
            >
              <InputNumber style={{ width: '100%' }} min={0} step={5} />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Form.Item
              name="delivery_fee_override"
              label={t('fieldDeliveryFee', lang)}
              // CHECK (delivery_fee_override IS NULL OR >= 0). Null means "use
              // the platform default", so an empty field is meaningful and is
              // not the same as zero.
            >
              <InputNumber style={{ width: '100%' }} min={0} step={1} />
            </Form.Item>
          </Col>
        </Row>

        <Row gutter={16}>
          <Col xs={24} md={8}>
            <Form.Item
              name="estimated_prep_time_minutes"
              label={t('fieldPrepMinutes', lang)}
              rules={rules.estimated_prep_time_minutes}
            >
              <InputNumber style={{ width: '100%' }} min={1} max={240} />
            </Form.Item>
          </Col>
          <Col xs={24} md={8}>
            <Form.Item
              name="estimated_delivery_minutes"
              label={t('fieldDeliveryMinutes', lang)}
              rules={rules.estimated_delivery_minutes}
            >
              <InputNumber style={{ width: '100%' }} min={1} max={240} />
            </Form.Item>
          </Col>
          <Col xs={24} md={8}>
            <Form.Item
              name="delivery_radius_km"
              label={t('fieldDeliveryRadius', lang)}
              rules={rules.delivery_radius_km}
            >
              <InputNumber style={{ width: '100%' }} min={1} max={100} step={0.5} />
            </Form.Item>
          </Col>
        </Row>

        <Row gutter={16}>
          <Col xs={24} md={8}>
            <Form.Item
              name="commission_pct"
              label={t('fieldCommission', lang)}
              rules={rules.commission_pct}
            >
              <InputNumber style={{ width: '100%' }} min={0} max={100} step={0.5} />
            </Form.Item>
          </Col>
          <Col xs={24} md={8}>
            <Form.Item
              name="payout_frequency"
              label={t('fieldPayoutFrequency', lang)}
            >
              <Select
                options={PAYOUT_FREQUENCIES.map((value) => ({
                  value,
                  // tStatus resolves the CHECK-constraint token to a label and falls
                  // back to the token itself for a value a later migration adds.
                  label: tStatus('status', value, lang),
                }))}
              />
            </Form.Item>
          </Col>
          <Col xs={24} md={8}>
            <Form.Item name="payout_method" label={t('fieldPayoutMethod', lang)}>
              <Select
                options={PAYOUT_METHODS.map((value) => ({
                  value,
                  label: tStatus('status', value, lang),
                }))}
              />
            </Form.Item>
          </Col>
        </Row>

        <Form.Item name="wallet_phone" label={t('fieldWalletPhone', lang)}>
          <Input />
        </Form.Item>

        <Row gutter={16}>
          <Col xs={24} md={12}>
            <Form.Item name="lat" label={t('fieldLat', lang)} rules={rules.lat}>
              <InputNumber style={{ width: '100%' }} step={0.000001} />
            </Form.Item>
          </Col>
          <Col xs={24} md={12}>
            <Form.Item name="lng" label={t('fieldLng', lang)} rules={rules.lng}>
              <InputNumber style={{ width: '100%' }} step={0.000001} />
            </Form.Item>
          </Col>
        </Row>

        {/* Only on create. On edit it would be a lie — the merchant is already
            reviewed, and the notice would imply an approval step that is not
            part of saving a name. */}
        {!isEdit && (
          <Alert
            type="info"
            showIcon
            // colorInfoBg rather than a literal tint, so the notice follows the
            // theme — see theme/tokens.ts.
            style={{ background: colors.colorNeutralSoft, border: 'none' }}
            message={t('newMerchantPendingNote', lang)}
          />
        )}
      </Form>
    </Modal>
  );
}