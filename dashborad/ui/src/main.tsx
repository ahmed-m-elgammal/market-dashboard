import { useMemo } from 'react';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { Authenticated, Refine } from '@refinedev/core';
// DEFAULT export in @refinedev/react-router 1.x (verified in its .d.ts), not a
// named `routerProvider` export.
import routerProvider from '@refinedev/react-router';
// Router primitives come from react-router directly, not from the Refine
// wrapper: react-router v7 is the peer dependency of @refinedev/react-router
// 1.x, and re-exporting them through the wrapper risks a version skew.
import { BrowserRouter, Navigate, Outlet, Route, Routes, useParams } from 'react-router';
import { RefineThemes, ThemedLayoutV2 } from '@refinedev/antd';
import { DashboardOutlined, ShopOutlined } from '@ant-design/icons';
import { ConfigProvider, App as AntApp, Typography } from 'antd';

import { authProvider, dataProvider } from './providers';
import { LangProvider, useLang } from './i18n/LangProvider';
import { buildI18nProvider } from './i18n/refineI18n';
import { t } from './i18n/strings';
import { AppHeader } from './components/layout/AppHeader';
import { LoginPage } from './pages/login/LoginPage';
import { OverviewPage } from './pages/overview/OverviewPage';
import { MerchantsPage } from './pages/merchants/MerchantsPage';
import { MerchantProfilePage } from './pages/merchants/MerchantProfilePage';
import { MerchantCategoriesPage } from './pages/merchants/MerchantCategoriesPage';
import { ItemViewPage } from './pages/items/ItemViewPage';
import { ItemEditPage } from './pages/items/ItemEditPage';
import { ErrorPage } from './pages/ErrorPage';

/**
 * Refine + Ant Design shell.
 *
 * useLang is consumed here so ConfigProvider picks the Ant Design locale and
 * the document direction. document.documentElement.dir is what actually drives
 * Ant Design's RTL layout — see LangProvider.
 */
/**
 * Sidebar title. `Title` is typed React.FC<TitleProps> in @refinedev/antd, so
 * this is passed as a COMPONENT, not called as a render prop. Reading lang from
 * the context keeps it reactive: switching language re-renders the sidebar
 * without remounting the layout.
 */
function BrandTitle() {
  const { lang } = useLang();
  return (
    <Typography.Text strong style={{ fontSize: 20, margin: 0 }}>
      {t('brandName', lang)}
      <Typography.Text type="secondary" style={{ fontSize: 12, marginInlineStart: 8 }}>
        {t('brandSuffix', lang)}
      </Typography.Text>
    </Typography.Text>
  );
}

/**
 * Route wrappers that pull their param out of the URL.
 *
 * React Router v7 hands params through context, not props, so a page component
 * cannot declare `({ itemId })`. These two keep that detail in one place instead
 * of pushing `useParams()` into every page — and they are the reason the page
 * components themselves take plain string props and stay trivially testable.
 */
function ItemRoute() {
  const { itemId = '' } = useParams();
  return <ItemViewPage itemId={itemId} />;
}

function ItemEditRoute() {
  const { itemId = '' } = useParams();
  return <ItemEditPage itemId={itemId} />;
}

function MerchantProfileRoute() {
  const { merchantId = '' } = useParams();
  return <MerchantProfilePage merchantId={merchantId} />;
}

function MerchantCategoriesRoute() {
  const { merchantId = '', categoryId } = useParams();
  // categoryId is optional on purpose: the same component serves the category
  // list alone (no selection yet) and the category list with a selected category.
  // Reading it from the URL rather than a second source means a shared link and
  // a click both resolve the same way.
  return <MerchantCategoriesPage merchantId={merchantId} categoryId={categoryId} />;
}

function Shell() {
  const { antdLocale, direction, lang, setLang } = useLang();

  // Rebuilt on each language change so the provider always closes over the
  // current language rather than the one from first render.
  const i18nProvider = useMemo(() => buildI18nProvider(lang, setLang), [lang, setLang]);

  return (
    <ConfigProvider locale={antdLocale} direction={direction} theme={RefineThemes.Blue}>
      <AntApp>
        <Refine
          authProvider={authProvider}
          dataProvider={dataProvider}
          i18nProvider={i18nProvider}
          routerProvider={routerProvider}
          // ThemedLayoutV2 builds its Sider menu from `resources`. Without this
          // the dashboard renders with an empty sidebar — the routes exist but
          // nothing links to them.
          resources={[
            {
              name: 'overview',
              list: '/',
              meta: { label: t('navDashboard', lang), icon: <DashboardOutlined /> },
            },
            {
              name: 'merchants',
              list: '/merchants',
              meta: { label: t('navMerchants', lang), icon: <ShopOutlined /> },
            },
          ]}
          options={{
            syncWithLocation: false,
            warnWhenUnsavedChanges: false,
            disableTelemetry: true,
          }}
        >
          <Routes>
            {/*
              EVERY authenticated route is wrapped in <Authenticated>.

              Without it the layout branch renders for anyone who types a URL:
              the sidebar, the Overview and every merchant screen would load,
              and only the individual data calls would fail. That is not a
              cosmetic gap — it means the dashboard's structure and its data
              shapes are readable without signing in, and it pushes the auth
              check onto every request instead of putting it once, at the door.

              It also redirects rather than rendering a shell: an unauthenticated
              visitor gets the login page and never sees a frame of the app.
            */}
            <Route
              element={
                <Authenticated key="authenticated" fallback={<Navigate to="/login" />}>
                  <ThemedLayoutV2 Header={AppHeader} Title={BrandTitle}>
                    <Outlet />
                  </ThemedLayoutV2>
                </Authenticated>
              }
            >
              <Route index element={<OverviewPage />} />

              {/* Merchants is one sidebar entry, but four screens. The nested
                  paths mirror the flow the operator actually walks:
                    list -> profile -> category -> items -> item
                  and the `meta.breadcrumb` titles give the layout a trail, so
                  the sidebar's single "Merchants" link does not leave a deep
                  page with no indication of where it sits. */}
              <Route path="/merchants" element={<MerchantsPage />} />
              <Route
                path="/merchants/:merchantId"
                element={<MerchantProfileRoute />}
                handle={{ breadcrumb: t('merchantsTitle', lang) }}
              />
              <Route
                path="/merchants/:merchantId/categories"
                element={<MerchantCategoriesRoute />}
                handle={{ breadcrumb: t('categoriesTitle', lang) }}
              />
              <Route
                path="/merchants/:merchantId/categories/:categoryId"
                element={<MerchantCategoriesRoute />}
                handle={{ breadcrumb: t('itemsTitle', lang) }}
              />

              {/* Items are addressed by item id alone, not nested under the
                  merchant. An item id is a UUID and is unique on its own, so
                  the extra path segments would be redundant — and every link
                  into an item would have to carry a merchant and a category it
                  does not need. The screens navigate back using the ids already
                  on the row. */}
              <Route
                path="/items/:itemId"
                element={<ItemRoute />}
                handle={{ breadcrumb: t('viewItem', lang) }}
              />
              <Route
                path="/items/:itemId/edit"
                element={<ItemEditRoute />}
                handle={{ breadcrumb: t('editItem', lang) }}
              />
            </Route>

            {/* Login and 404 live OUTSIDE the layout branch. React Router ranks
                by specificity, so a '*' inside the layout branch would win over
                both of these and make /login unreachable. */}
            <Route path="/login" element={<LoginPage />} />
            <Route path="*" element={<ErrorPage />} />
          </Routes>
        </Refine>
      </AntApp>
    </ConfigProvider>
  );
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <LangProvider>
        <Shell />
      </LangProvider>
    </BrowserRouter>
  </React.StrictMode>,
);