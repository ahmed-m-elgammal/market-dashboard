/**
 * Dashboard header: language toggle, signed-in admin, sign-out.
 *
 * The toggle flips the document direction too, so the whole layout mirrors —
 * see LangProvider.
 *
 * The demo reset control appears ONLY in demo mode. It is in the header rather
 * than a settings screen because its whole purpose is to be reachable in one
 * click while looking at a screen that has been edited into a strange state,
 * which is exactly when someone needs it.
 */
import { App, Avatar, Button, Dropdown, Popconfirm, Space, Tag, Typography } from 'antd';
import type { MenuProps } from 'antd';
import { GlobalOutlined, LogoutOutlined, ReloadOutlined, UserOutlined } from '@ant-design/icons';
import { useLogout, useGetIdentity } from '@refinedev/core';
import { DATA_MODE } from '../../providers';
import { overlayEditCount, resetOverlay } from '../../demo/store';
import { useLang } from '../../i18n/LangProvider';
import { fmt, t } from '../../i18n/strings';

export function AppHeader() {
  const { lang, setLang } = useLang();
  const { mutate: logout } = useLogout();
  const { message } = App.useApp();
  const { data: identity } = useGetIdentity<{
    id: string;
    email: string;
    fullName: string | null;
    role: string;
  }>();

  const items: MenuProps['items'] = [
    {
      key: 'en',
      label: t('langEnglish', lang),
      onClick: () => setLang('en'),
    },
    {
      key: 'ar',
      label: t('langArabic', lang),
      onClick: () => setLang('ar'),
    },
  ];

  const initials = (identity?.fullName ?? identity?.email ?? 'A')
    .split(/[\s@.]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');

  const onReset = () => {
    resetOverlay();
    message.success(t('resetDemoDone', lang));
    // A full reload rather than invalidating queries: the reset touches every
    // collection at once, and a reload cannot leave one screen showing a row the
    // others have forgotten about.
    window.location.reload();
  };

  const editCount = DATA_MODE === 'demo' ? overlayEditCount() : 0;

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'flex-end',
        gap: 12,
        // An explicit height, NOT height: '100%'.
        //
        // ThemedLayoutV2 renders this component inside a plain wrapper div that
        // has no height of its own, so a percentage height resolves against the
        // whole content column instead of a header row. The result was a 376px
        // "header" with the page content pushed below the fold. Naming the height
        // makes the row 64px, matching the sidebar's title band above it.
        height: 64,
        width: '100%',
        paddingInline: 16,
      }}
    >
      {DATA_MODE === 'demo' && (
        <Tag
          bordered={false}
          // A preset, deliberately: Tag's API takes presets, and this one is
          // context rather than a status — there is no semantic token for "you
          // are looking at sample data", and inventing one would put a
          // dashboard-only meaning into the shared palette.
          color="blue"
          icon={<ReloadOutlined />}
        >
          {editCount > 0
            ? fmt(t('demoEditsCount', lang), { n: editCount })
            : t('demoBanner', lang)}
        </Tag>
      )}

      <Dropdown menu={{ items, selectedKeys: [lang] }} trigger={['click']}>
        <Button type="text" icon={<GlobalOutlined />}>
          {t(lang === 'ar' ? 'langArabic' : 'langEnglish', lang)}
        </Button>
      </Dropdown>

      <Space size={8}>
        <Avatar size="small" icon={<UserOutlined />}>
          {initials || undefined}
        </Avatar>
        <Typography.Text type="secondary" style={{ fontSize: 13 }}>
          {identity?.fullName ?? identity?.email ?? ''}
        </Typography.Text>

        {DATA_MODE === 'demo' && (
          <Popconfirm
            title={t('resetDemoConfirm', lang)}
            onConfirm={onReset}
            okText={t('resetDemoData', lang)}
            cancelText={t('cancel', lang)}
          >
            <Button
              type="text"
              icon={<ReloadOutlined />}
              aria-label={t('resetDemoData', lang)}
            />
          </Popconfirm>
        )}

        <Button
          type="text"
          danger
          icon={<LogoutOutlined />}
          onClick={() => logout()}
          aria-label={t('signOut', lang)}
        />
      </Space>
    </div>
  );
}