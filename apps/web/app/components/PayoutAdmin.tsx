'use client';

import { useState, useTransition } from 'react';
import type { FormState } from '../actions';

export interface PayoutLabels {
  record: string;
  amount: string;
  paidAt: string;
  method: string;
  reference: string;
  note: string;
  review: string;
  confirmLine: string;
  confirm: string;
  back: string;
  overWarn: string;
  recorded: string;
  newOwed: string;
  newOwing: string;
  voidBtn: string;
  voidReasonPh: string;
  voidConfirm: string;
  voidDone: string;
  alreadyVoided: string;
  methods: Record<string, string>;
  /** Pre-formatted for the current language. */
  currency: string;
  locale: string;
}

type Action = (state: FormState, fd: FormData) => Promise<FormState>;

const fmt = (n: number, l: PayoutLabels) => `${new Intl.NumberFormat(l.locale).format(n)} ${l.currency}`;

/** Record-payout form with a confirm step. Over-paying warns but is still allowed. */
export function RecordPayout({ orgId, orgName, owedMmk, defaultPaidAt, action, labels, errorText }: { orgId: string; orgName: string; owedMmk: number; defaultPaidAt: string; action: Action; labels: PayoutLabels; errorText: Record<string, string> }) {
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<'edit' | 'confirm'>('edit');
  const [pending, start] = useTransition();
  const [state, setState] = useState<FormState>({});
  const [amount, setAmount] = useState('');
  const [paidAt, setPaidAt] = useState(defaultPaidAt);
  const [method, setMethod] = useState('BANK');
  const [reference, setReference] = useState('');
  const [note, setNote] = useState('');
  const amountN = Number(amount);
  const valid = Number.isSafeInteger(amountN) && amountN > 0;
  const over = valid && amountN > owedMmk;

  const submit = () => {
    const fd = new FormData();
    fd.set('orgId', orgId);
    fd.set('amountMmk', String(amountN));
    fd.set('paidAt', paidAt);
    fd.set('method', method);
    fd.set('reference', reference);
    fd.set('note', note);
    start(async () => {
      const r = await action({}, fd);
      setState(r);
      setStep('edit');
      if (r.ok) {
        setAmount('');
        setReference('');
        setNote('');
      }
    });
  };

  if (!open && !state.ok) {
    return <button type="button" className="secondary" onClick={() => setOpen(true)}>{labels.record}</button>;
  }
  const newOwed = typeof state.data?.owedMmk === 'number' ? state.data.owedMmk : null;
  return (
    <div className="card" data-testid={`record-${orgId}`}>
      <strong>{labels.record}: {orgName}</strong>
      {state.error && <div className="error">{errorText[state.error] ?? state.error}</div>}
      {state.ok && (
        <div className="ok" data-testid="payout-ok">
          {labels.recorded}{' '}
          {newOwed !== null && (newOwed < 0 ? labels.newOwing.replace('{amount}', fmt(-newOwed, labels)) : labels.newOwed.replace('{amount}', fmt(newOwed, labels)))}
        </div>
      )}
      {step === 'edit' ? (
        <form onSubmit={(e) => { e.preventDefault(); if (valid) setStep('confirm'); }}>
          <div className="grid">
            <div className="field"><label>{labels.amount}</label><input name="amountMmk" type="number" min={1} step={1} required value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <div className="field"><label>{labels.paidAt}</label><input type="datetime-local" required value={paidAt} onChange={(e) => setPaidAt(e.target.value)} /></div>
            <div className="field">
              <label>{labels.method}</label>
              <select value={method} onChange={(e) => setMethod(e.target.value)}>
                {Object.entries(labels.methods).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
            <div className="field"><label>{labels.reference}</label><input maxLength={200} value={reference} onChange={(e) => setReference(e.target.value)} /></div>
            <div className="field"><label>{labels.note}</label><input maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} /></div>
          </div>
          <button type="submit" disabled={!valid}>{labels.review}</button>
        </form>
      ) : (
        <div data-testid="payout-confirm">
          <p>{labels.confirmLine.replace('{method}', labels.methods[method] ?? method).replace('{amount}', fmt(amountN, labels)).replace('{org}', orgName).replace('{date}', paidAt.replace('T', ' '))}</p>
          {over && <div className="error" data-testid="payout-over-warning">{labels.overWarn.replace('{owed}', fmt(Math.max(owedMmk, 0), labels))}</div>}
          <div className="row">
            <button type="button" disabled={pending} aria-busy={pending} onClick={submit}>{pending ? '…' : labels.confirm}</button>
            <button type="button" className="secondary" disabled={pending} onClick={() => setStep('edit')}>{labels.back}</button>
          </div>
        </div>
      )}
    </div>
  );
}

/** Void button: asks for a reason, then a confirm step. */
export function VoidPayout({ id, action, labels, errorText }: { id: string; action: Action; labels: PayoutLabels; errorText: Record<string, string> }) {
  const [step, setStep] = useState<'idle' | 'reason' | 'confirm'>('idle');
  const [reason, setReason] = useState('');
  const [pending, start] = useTransition();
  const [state, setState] = useState<FormState>({});
  const submit = () => {
    const fd = new FormData();
    fd.set('id', id);
    fd.set('reason', reason.trim());
    start(async () => {
      setState(await action({}, fd));
      setStep('idle');
    });
  };
  return (
    <div>
      {state.error && <div className="error">{errorText[state.error] ?? state.error}</div>}
      {state.ok && <div className="ok">{labels.voidDone}</div>}
      {step === 'idle' && <button type="button" className="danger" onClick={() => setStep('reason')}>{labels.voidBtn}</button>}
      {step === 'reason' && (
        <form onSubmit={(e) => { e.preventDefault(); if (reason.trim().length >= 3) setStep('confirm'); }}>
          <input placeholder={labels.voidReasonPh} required minLength={3} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
          <div className="row" style={{ marginTop: 6 }}>
            <button type="submit" className="danger">{labels.voidBtn}</button>
            <button type="button" className="secondary" onClick={() => setStep('idle')}>{labels.back}</button>
          </div>
        </form>
      )}
      {step === 'confirm' && (
        <div data-testid="void-confirm">
          <p>{labels.voidConfirm}</p>
          <div className="row">
            <button type="button" className="danger" disabled={pending} aria-busy={pending} onClick={submit}>{pending ? '…' : labels.voidBtn}</button>
            <button type="button" className="secondary" disabled={pending} onClick={() => setStep('reason')}>{labels.back}</button>
          </div>
        </div>
      )}
    </div>
  );
}
