/**
 * Login — Supabase Auth email + password, then a role check.
 *
 * The role check is not decoration: signInWithPassword succeeds for ANY valid
 * account, including customers. Without the check a customer would land on a
 * dashboard that renders and then fails every privileged call, which is a worse
 * experience than a clear rejection. authProvider does the check and signs such
 * a session out immediately; this page only renders the outcome.
 */
import { useState } from 'react';
import { useLogin } from '@refinedev/core';
import { useNavigate } from 'react-router';
import { Alert, Button, Card, Form, Input, Layout, Space, Typography } from 'antd';
import { LockOutlined, MailOutlined } from '@ant-design/icons';
import { AuthError } from '../../authProvider';
import { DATA_MODE } from '../../providers';
import { demoAdminHint } from '../../authProviderDemo';
import { useLang } from '../../i18n/LangProvider';
import { fmt, t } from '../../i18n/strings';

/**
 * Matches authProvider's login signature: authProvider reads `username ?? email`,
 * so `email` is the form field and the mapping happens in one place.
 */
interface LoginFormValues {
  username: string;
  password: string;
}

export function LoginPage() {
  // Refine v4 returns a react-query UseMutationResult here, so { mutate } is the
  // correct shape.
  const { mutate: login, isLoading } = useLogin<LoginFormValues>();
  const { lang } = useLang();
  const [form] = Form.useForm<LoginFormValues>();
  const [failure, setFailure] = useState<{ en: string; ar: string } | null>(null);
  const navigate = useNavigate();

  const onFinish = (values: LoginFormValues) => {
    setFailure(null);
    login(
      {
        username: values.username,
        password: values.password,
      },
      {
        onError: (error: unknown) => {
          // Bilingual: show whichever matches the active language, falling back
          // to English so the message is never blank.
          const authError = error as AuthError;
          const en =
            authError?.code === 'NOT_ADMIN'
              ? t('loginNotAdmin', 'en')
              : authError?.code === 'INVALID_CREDENTIALS'
                ? t('loginInvalidCredentials', 'en')
                : (authError?.message ?? t('unexpectedError', 'en'));
          const ar =
            authError?.code === 'NOT_ADMIN'
              ? t('loginNotAdmin', 'ar')
              : authError?.code === 'INVALID_CREDENTIALS'
                ? t('loginInvalidCredentials', 'ar')
                : (authError?.message ?? t('unexpectedError', 'ar'));

          // Rendered inline as an Alert rather than a toast: a failed sign-in is
          // the page's answer, not a transient event, and AntD's notification
          // stack is not wired up in this shell.
          setFailure({ en, ar });
        },
        onSuccess: () => navigate('/', { replace: true }),
      },
    );
  };

  return (
    <Layout style={{ minHeight: '100vh', justifyContent: 'center' }}>
      <Layout.Content
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 24,
        }}
      >
        <Card style={{ width: 400, maxWidth: '100%' }}>
          <Space direction="vertical" size="large" style={{ width: '100%' }}>
            <Space direction="vertical" size={0}>
              <Typography.Title level={3} style={{ margin: 0 }}>
                {t('appName', lang)}
              </Typography.Title>
              <Typography.Text type="secondary">
                {t('loginTitle', lang)}
              </Typography.Text>
            </Space>

            {failure && (
              <Alert
                type="error"
                showIcon
                message={t('loginFailed', lang)}
                description={lang === 'ar' ? failure.ar : failure.en}
              />
            )}

            <Form<LoginFormValues>
              form={form}
              layout="vertical"
              requiredMark={false}
              onFinish={onFinish}
              initialValues={{ username: '', password: '' }}
            >
              <Form.Item
                name="username"
                label={t('loginEmail', lang)}
                rules={[
                  { required: true, message: t('loginEmail', lang) },
                  { type: 'email', message: t('emailInvalid', lang) },
                ]}
              >
                <Input
                  prefix={<MailOutlined />}
                  type="email"
                  autoComplete="username"
                  size="large"
                />
              </Form.Item>

              <Form.Item
                name="password"
                label={t('loginPassword', lang)}
                rules={[{ required: true, message: t('loginPassword', lang) }]}
              >
                <Input.Password
                  prefix={<LockOutlined />}
                  autoComplete="current-password"
                  size="large"
                />
              </Form.Item>

              <Button
                type="primary"
                htmlType="submit"
                size="large"
                block
                loading={isLoading}
              >
                {isLoading ? t('loginSigningIn', lang) : t('loginSubmit', lang)}
              </Button>
            </Form>

            {/* Demo mode has no password to check, so the form would otherwise be
                a dead end for anyone without the credentials. Stating them is
                honest — a demo that fakes a real sign-in would be misleading about
                what is actually being verified. */}
            {DATA_MODE === 'demo' && (
              <Alert
                type="info"
                showIcon
                message={fmt(t('demoSignInHint', lang), { email: demoAdminHint() })}
              />
            )}
          </Space>
        </Card>
      </Layout.Content>
    </Layout>
  );
}