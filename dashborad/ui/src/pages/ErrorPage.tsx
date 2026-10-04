/**
 * 404 / unmatched route.
 *
 * Rendered OUTSIDE ThemedLayoutV2 (see main.tsx) because a route that failed to
 * match should not appear inside the chrome of the app it failed to reach.
 */
import { Button, Result } from 'antd';
import { useNavigate } from 'react-router';
import { useLang } from '../i18n/LangProvider';
import { t } from '../i18n/strings';

export function ErrorPage() {
  const { lang } = useLang();
  const navigate = useNavigate();

  return (
    <Result
      status="404"
      title={t('errorNotFoundTitle', lang)}
      subTitle={t('errorNotFoundBody', lang)}
      extra={
        <Button type="primary" onClick={() => navigate('/', { replace: true })}>
          {t('backToDashboard', lang)}
        </Button>
      }
    />
  );
}