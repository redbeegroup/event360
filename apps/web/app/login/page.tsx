import { loginAction } from '../actions';
import { ActionForm } from '../components/ActionForm';
import { PageHeader } from '../components/PageHeader';
import { t } from '../lib/i18n';

export default async function LoginPage() {
  const tr = await t();
  return (
    <div className="auth-box card">
      <PageHeader title={tr.appName} />
      <ActionForm action={loginAction} submitLabel={tr.login} variant="gold" errorText={{ invalid: tr.invalidLogin }}>
        <div className="field">
          <label htmlFor="email">{tr.email}</label>
          <input id="email" name="email" type="email" autoComplete="username" required />
        </div>
        <div className="field">
          <label htmlFor="password">{tr.password}</label>
          <input id="password" name="password" type="password" autoComplete="current-password" required />
        </div>
      </ActionForm>
    </div>
  );
}
