import { ActionForm } from '../../components/ActionForm';
import { api } from '../../lib/api';
import { fmtDate, t } from '../../lib/i18n';
import { saveSmsSettingsAction, sendTestSmsAction } from '../actions';

export const dynamic = 'force-dynamic';

interface SmsView {
  provider: string;
  apiKey: string | null;
  apiSecretSet: boolean;
  apiSecretHint: string | null;
  senderId: string;
  enabled: boolean;
  testMode: boolean;
  otpTemplate: string;
  canStoreSecrets: boolean;
  balance: { balance: number; currency: string } | null;
  balanceError: string | null;
}

interface SmsLogRow {
  id: string;
  to: string;
  purpose: string;
  status: string;
  error: string | null;
  testMode: boolean;
  providerMessageId: string | null;
  createdAt: string;
}

export default async function SettingsPage() {
  const [tr, sms, log] = await Promise.all([t(), api<SmsView>('/admin/settings/sms'), api<SmsLogRow[]>('/admin/sms-log?limit=20')]);
  const configured = !!sms.apiKey && sms.apiSecretSet && !!sms.senderId;
  const preview = sms.otpTemplate.replaceAll('{code}', '482913').replaceAll('{minutes}', '5');
  return (
    <>
      <h1>{tr.settings}</h1>
      <h2>{tr.smsTitle}</h2>
      <div className="card">
        <p className="muted">{tr.smsHint}</p>
        <p>
          {tr.status}:{' '}
          <span className={`badge ${sms.enabled && configured ? 'PUBLISHED' : 'SUBMITTED'}`}>
            {sms.enabled && configured ? tr.smsOn : configured ? tr.smsOff : tr.smsNotConfigured}
          </span>{' '}
          {sms.testMode && <span className="badge SUBMITTED">{tr.smsTestMode}</span>}
        </p>
        {configured && (
          <p>
            {tr.smsBalance}:{' '}
            {sms.balance ? <strong>{sms.balance.balance.toLocaleString()} {sms.balance.currency}</strong> : <span className="error-text">{sms.balanceError}</span>}
          </p>
        )}
        {!sms.canStoreSecrets && <div className="error">{tr.smsNoKey}</div>}
        <ActionForm action={saveSmsSettingsAction} submitLabel={tr.save} okText={{ saved: tr.saved }}>
          <div className="grid">
            <div className="field">
              <label>{tr.smsApiKey}</label>
              <input name="apiKey" autoComplete="off" placeholder={sms.apiKey ?? ''} />
              {sms.apiKey && <small className="muted">{tr.smsKeepHint}</small>}
            </div>
            <div className="field">
              <label>{tr.smsApiSecret}</label>
              <input name="apiSecret" type="password" autoComplete="new-password" placeholder={sms.apiSecretHint ?? ''} />
              {sms.apiSecretSet && <small className="muted">{tr.smsKeepHint}</small>}
            </div>
            <div className="field">
              <label>{tr.smsSender}</label>
              <input name="senderId" defaultValue={sms.senderId} maxLength={20} placeholder="SMSPoh" />
              <small className="muted">{tr.smsSenderHint}</small>
            </div>
          </div>
          <div className="field">
            <label>{tr.smsTemplate}</label>
            <input name="otpTemplate" defaultValue={sms.otpTemplate} maxLength={300} required />
            <small className="muted">{tr.smsTemplateHint} — {preview} ({preview.length} / 160)</small>
          </div>
          <label className="check"><input type="checkbox" name="enabled" defaultChecked={sms.enabled} /> {tr.smsEnabled}</label>
          <label className="check"><input type="checkbox" name="testMode" defaultChecked={sms.testMode} /> {tr.smsTestModeLabel}</label>
        </ActionForm>
      </div>

      {configured && (
        <>
          <h2>{tr.smsTest}</h2>
          <div className="card">
            <ActionForm action={sendTestSmsAction} submitLabel={tr.smsSendTest} okText={{ testSent: tr.smsTestSent }}>
              <div className="field" style={{ maxWidth: 320 }}>
                <label>{tr.phone}</label>
                <input name="phone" inputMode="tel" placeholder="09xxxxxxxxx" required />
              </div>
            </ActionForm>
          </div>
        </>
      )}

      <h2>{tr.smsLog}</h2>
      <div className="card table-wrap">
        {log.length === 0 ? (
          <p className="muted">{tr.nothingYet}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.time}</th><th>{tr.phone}</th><th>{tr.smsPurpose}</th><th>{tr.status}</th><th /></tr></thead>
            <tbody>
              {log.map((l) => (
                <tr key={l.id}>
                  <td>{fmtDate(l.createdAt, tr.lang)}</td>
                  <td>{l.to}</td>
                  <td>{l.purpose === 'otp' ? tr.smsPurposeOtp : tr.smsPurposeTest}{l.testMode ? ` · ${tr.smsTestMode}` : ''}</td>
                  <td><span className={`badge ${l.status === 'accepted' ? 'PUBLISHED' : 'REJECTED'}`}>{l.status === 'accepted' ? tr.smsAccepted : tr.smsFailed}</span></td>
                  <td className="muted">{l.error ?? ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
