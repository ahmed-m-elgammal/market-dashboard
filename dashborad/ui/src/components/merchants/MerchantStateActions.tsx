/**
 * Approve / reject / publish controls for one merchant.
 *
 * WHY TWO GROUPS AND NOT ONE ROW OF BUTTONS
 *
 * Approval and publication are different decisions about different things.
 * Approval is a judgement: has Ops looked at this vendor? Publication is a
 * runtime switch: should customers see them right now? Collapsing them is how an
 * unreviewed merchant becomes visible, because the customer feed filters on
 * is_active and never reads approval_status.
 *
 * So the two live in separate cards, the order matches the actual sequence
 * (review, then publish), and "Publish" is disabled with an explanation until the
 * merchant is approved. The disabled state is the guard, and it is duplicated
 * server-side on purpose — the UI copy is a courtesy, admin-api is the rule.
 *
 * The state machine is enforced in the store and in admin-api, not here. This
 * component reflects what is possible and explains what is not; it does not
 * decide.
 */
import { useState } from 'react';
import { useUpdate } from '@refinedev/core';
import {
  Alert,
  App,
  Button,
  Card,
  Col,
  Descriptions,
  Flex,
  Input,
  Modal,
  Row,
  Space,
  Tooltip,
  Typography,
} from 'antd';
import {
  CheckCircleOutlined,
  CloseCircleOutlined,
  EyeOutlined,
  RollbackOutlined,
  StopOutlined,
} from '@ant-design/icons';
import type { MerchantRow } from '../../pages/merchants/MerchantsPage';
import { useLang } from '../../i18n/LangProvider';
import { errorText, t, tStatus, type StringKey } from '../../i18n/strings';
import { useSemanticColors } from '../../theme/tokens';

/** The transitions the backend understands, in the order they are offered. */
type StateAction = 'approve' | 'unapprove' | 'reject' | 'publish' | 'unpublish';

/**
 * Map an error code from the provider onto a message.
 *
 * The demo and admin-api return the same code strings, so this works in both
 * modes. Unknown codes fall back to the provider's own bilingual text rather
 * than inventing one — a missing translation should degrade, not blank out.
 */
const STATE_ERROR_KEY: Record<string, StringKey> = {
  ALREADY_APPROVED: 'stateAlreadyApproved',
  ALREADY_REJECTED: 'stateAlreadyRejected',
  NOT_APPROVED: 'stateNotApproved',
  ALREADY_PUBLISHED: 'stateAlreadyPublished',
  NOT_PUBLISHED: 'stateNotPublished',
  NOTE_REQUIRED: 'stateNoteRequired',
  NOT_FOUND: 'stateNotFound',
};

export function MerchantStateActions({ merchant }: { merchant: MerchantRow }) {
  const { lang } = useLang();
  const colors = useSemanticColors();
  const { message } = App.useApp();

  const { mutate: run, isLoading } = useUpdate();

  // Modals that need input from the operator.
  const [approveOpen, setApproveOpen] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [approveNote, setApproveNote] = useState('');
  const [rejectReason, setRejectReason] = useState('');
  const [rejectError, setRejectError] = useState<string | null>(null);

  const isApproved = merchant.approval_status === 'approved';
  const isRejected = merchant.approval_status === 'rejected';
  const isLive = merchant.is_active;

  /** Fire a transition and report the specific reason if the server refuses. */
  const apply = (action: StateAction, opts?: { note?: string; confirm?: string }) => {
    run(
      {
        resource: 'merchants',
        id: merchant.id,
        values: { action, ...(opts?.note ? { note: opts.note } : {}) } as never,
      },
      {
        onSuccess: () => {
          setApproveOpen(false);
          setRejectOpen(false);
          setApproveNote('');
          setRejectReason('');
          setRejectError(null);
          message.success(
            lang === 'ar'
              ? {
                  approve: 'تم اعتماد التاجر.',
                  unapprove: 'تم سحب الاعتماد.',
                  reject: 'تم رفض التاجر.',
                  publish: 'تم نشر التاجر.',
                  unpublish: 'تم إلغاء نشر التاجر.',
                }[action]
              : {
                  approve: 'Merchant approved.',
                  unapprove: 'Approval withdrawn.',
                  reject: 'Merchant rejected.',
                  publish: 'Merchant published.',
                  unpublish: 'Merchant unpublished.',
                }[action],
          );
        },
        onError: (error: unknown) => {
          const code =
            typeof error === 'object' && error !== null && 'code' in error
              ? String((error as { code: unknown }).code)
              : '';
          const key = STATE_ERROR_KEY[code];

          // Reject keeps the operator in the modal so the reason is not lost;
          // everything else surfaces as a toast.
          if (action === 'reject') {
            setRejectError(key ? t(key, lang) : errorText(error, lang));
            return;
          }
          message.error(key ? t(key, lang) : errorText(error, lang));
        },
      },
    );
  };

  const submitReject = () => {
    const reason = rejectReason.trim();
    if (!reason) {
      setRejectError(t('actionRejectReasonRequired', lang));
      return;
    }
    apply('reject', { note: reason });
  };

  return (
    <>
      {/* gutter, not gap: this antd version's Row has no gap prop. */}
      <Row gutter={[16, 16]}>
        {/* Review: a judgement about the vendor. */}
        <Col xs={24} lg={12}>
          <Card
            title={t('approvalSection', lang)}
            variant="outlined"
            extra={
              <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                {isApproved
                  ? t('approvalGranted', lang)
                  : isRejected
                    ? t('approvalRejected', lang)
                    : t('approvalAwaitingReview', lang)}
              </Typography.Text>
            }
          >
            <Descriptions size="small" column={1} style={{ marginBottom: 12 }}>
              <Descriptions.Item label={tStatus('approval', merchant.approval_status, lang)}>
                <Typography.Text
                  type={isApproved ? 'success' : isRejected ? 'danger' : 'warning'}
                >
                  {tStatus('approval', merchant.approval_status, lang)}
                </Typography.Text>
              </Descriptions.Item>
              {merchant.approval_note && (
                <Descriptions.Item label={t('actionApproveNote', lang)}>
                  {merchant.approval_note}
                </Descriptions.Item>
              )}
            </Descriptions>

            <Space wrap>
              {!isApproved && (
                <Button
                  type="primary"
                  icon={<CheckCircleOutlined />}
                  loading={isLoading}
                  onClick={() => setApproveOpen(true)}
                >
                  {t('actionApprove', lang)}
                </Button>
              )}

              {isApproved && (
                <Button
                  icon={<RollbackOutlined />}
                  loading={isLoading}
                  onClick={() =>
                    apply('unapprove', {
                      confirm: t('actionUnapproveConfirm', lang),
                    })
                  }
                >
                  {t('actionUnapprove', lang)}
                </Button>
              )}

              {!isRejected && (
                <Button
                  danger
                  icon={<CloseCircleOutlined />}
                  loading={isLoading}
                  onClick={() => setRejectOpen(true)}
                >
                  {t('actionReject', lang)}
                </Button>
              )}
            </Space>
          </Card>
        </Col>

        {/* Visibility: a runtime switch, only meaningful once approved. */}
        <Col xs={24} lg={12}>
          <Card
            title={t('publicationSection', lang)}
            variant="outlined"
            extra={
              <Typography.Text
                type={isLive ? 'success' : 'secondary'}
                style={{ fontSize: 12 }}
              >
                {isLive ? t('published_visible', lang) : t('unpublished_hidden', lang)}
              </Typography.Text>
            }
          >
            {!isApproved && (
              <Alert
                type="info"
                showIcon
                style={{ marginBottom: 12, background: colors.colorNeutralSoft, border: 'none' }}
                message={t('publishNeedsApproval', lang)}
              />
            )}

            {isLive ? (
              <Button
                danger
                icon={<StopOutlined />}
                loading={isLoading}
                onClick={() =>
                  apply('unpublish', { confirm: t('actionUnpublishConfirm', lang) })
                }
              >
                {t('actionUnpublish', lang)}
              </Button>
            ) : (
              <Tooltip title={!isApproved ? t('publishNeedsApproval', lang) : undefined}>
                <Button
                  type="primary"
                  icon={<EyeOutlined />}
                  loading={isLoading}
                  // Disabled rather than hidden: an operator needs to know the
                  // action exists and why it is unavailable, not to find it
                  // missing and wonder whether they missed a menu.
                  disabled={!isApproved}
                  onClick={() => apply('publish')}
                >
                  {t('actionPublish', lang)}
                </Button>
              </Tooltip>
            )}
          </Card>
        </Col>
      </Row>

      {/* Approve: note is optional and recorded with the decision. */}
      <Modal
        open={approveOpen}
        title={t('actionApproveTitle', lang)}
        okText={t('actionApprove', lang)}
        cancelText={t('cancel', lang)}
        confirmLoading={isLoading}
        onCancel={() => setApproveOpen(false)}
        onOk={() => apply('approve', { note: approveNote.trim() || undefined })}
      >
        <Typography.Paragraph type="secondary" style={{ marginBottom: 8 }}>
          {t('actionApproveNote', lang)}
        </Typography.Paragraph>
        <Input.TextArea
          rows={3}
          value={approveNote}
          onChange={(e) => setApproveNote(e.target.value)}
        />
      </Modal>

      {/* Reject: a reason is mandatory, because a rejection with no explanation
          is unusable to the merchant and indistinguishable from a mistake. */}
      <Modal
        open={rejectOpen}
        title={t('actionRejectTitle', lang)}
        okText={t('actionReject', lang)}
        cancelText={t('cancel', lang)}
        okButtonProps={{ danger: true }}
        confirmLoading={isLoading}
        onCancel={() => {
          setRejectOpen(false);
          setRejectError(null);
        }}
        onOk={submitReject}
      >
        <Flex vertical gap={8}>
          <Typography.Text strong>{t('actionRejectReasonLabel', lang)}</Typography.Text>
          <Input.TextArea
            rows={3}
            value={rejectReason}
            onChange={(e) => {
              setRejectReason(e.target.value);
              setRejectError(null);
            }}
          />
          {rejectError && (
            <Typography.Text type="danger" style={{ fontSize: 12 }}>
              {rejectError}
            </Typography.Text>
          )}
        </Flex>
      </Modal>
    </>
  );
}