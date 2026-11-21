import { acceptInviteAction } from '../../actions';
import { ActionForm } from '../../components/ActionForm';
import { PageHeader } from '../../components/PageHeader';
import { api, ApiError } from '../../lib/api';
import { t } from '../../lib/i18n';

export const dynamic = 'force-dynamic';

interface InviteInfo {
  email: string;
  organization: string | null;
  orgRole: string | null;
  platformRole: string | null;
  existingAccount?: boolean;
}

export default async function InvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const tr = await t();
  let info: InviteInfo | null = null;
  let error: string | null = null;
  try {
    info = await api<InviteInfo>(`/auth/invitations/${encodeURIComponent(token)}`, { auth: false });
  } catch (e) {
    error = e instanceof ApiError ? e.message : 'Error';
  }
  return (
    <div className="auth-box card">
      <PageHeader title={tr.acceptInvite} />
      {error && <div className="error">{error}</div>}
      {info && (
        <>
          <p>
            {info.platformRole === 'PLATFORM_ADMIN' ? tr.invitedAsAdmin : `${tr.invitedTo}: `}
            {info.organization && <strong>{info.organization}</strong>}
            {info.orgRole && <> ({tr.roles[info.orgRole] ?? info.orgRole})</>}
          </p>
          <p className="muted">{info.email}</p>
          <ActionForm action={acceptInviteAction} submitLabel={tr.acceptInvite} variant="gold">
            <input type="hidden" name="token" value={token} />
            {info.existingAccount ? (
              <>
                <p className="muted">{tr.inviteExistingAccount}</p>
                <div className="field">
                  <label htmlFor="password">{tr.currentPassword}</label>
                  <input id="password" name="password" type="password" autoComplete="current-password" required />
                </div>
              </>
            ) : (
              <>
                <div className="field">
                  <label htmlFor="displayName">{tr.displayName}</label>
                  <input id="displayName" name="displayName" autoComplete="name" />
                </div>
                <div className="field">
                  <label htmlFor="password">{tr.newPassword}</label>
                  <input id="password" name="password" type="password" minLength={10} autoComplete="new-password" required />
                </div>
              </>
            )}
          </ActionForm>
        </>
      )}
    </div>
  );
}
