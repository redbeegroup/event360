'use client';

import { ReactNode, useActionState } from 'react';
import { useFormStatus } from 'react-dom';
import type { FormState } from '../actions';

function SubmitButton({ label, variant }: { label: string; variant?: 'secondary' | 'danger' | 'gold' }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className={variant === 'gold' ? 'btn-gold' : variant} disabled={pending} aria-busy={pending}>
      {pending ? '…' : label}
    </button>
  );
}

/** A form bound to a server action; shows its error/problems/ok message and an optional result block. */
export function ActionForm({
  action,
  submitLabel,
  children,
  variant,
  confirm,
  errorText,
  okText,
  inviteLabels,
  className,
  id,
}: {
  action: (state: FormState, fd: FormData) => Promise<FormState>;
  submitLabel: string;
  children?: ReactNode;
  /** gold = the page's single main action; omitted = navy filled. */
  variant?: 'secondary' | 'danger' | 'gold';
  confirm?: string;
  errorText?: Record<string, string>;
  okText?: Record<string, string>;
  /** When the action returns data.inviteUrl, show it with these labels and a copy button. */
  inviteLabels?: { text: string; copy: string };
  className?: string;
  /** Lets a button elsewhere on the page submit this form (`form` attribute). */
  id?: string;
}) {
  const [state, formAction] = useActionState(action, {} as FormState);
  return (
    <form
      action={formAction}
      id={id}
      className={className}
      onSubmit={(e) => {
        if (confirm && !window.confirm(confirm)) e.preventDefault();
      }}
    >
      {state.error && <div className="error">{errorText?.[state.error] ?? state.error}</div>}
      {state.problems?.length ? (
        <div className="error">
          <ul className="fine-list">{state.problems.map((p) => <li key={p}>{p}</li>)}</ul>
        </div>
      ) : null}
      {state.ok && <div className="ok">{okText?.[state.ok] ?? state.ok}</div>}
      {typeof state.data?.inviteUrl === 'string' && inviteLabels && (
        <div className="ok">
          {typeof state.data.name === 'string' && <strong>{state.data.name}</strong>}
          <p style={{ margin: '6px 0' }}>{inviteLabels.text}</p>
          <CopyBox value={state.data.inviteUrl} label={inviteLabels.copy} />
        </div>
      )}
      {children}
      <SubmitButton label={submitLabel} variant={variant} />
    </form>
  );
}

export function CopyBox({ value, label }: { value: string; label: string }) {
  return (
    <div className="field">
      <div className="code">{value}</div>
      <button type="button" className="secondary" style={{ marginTop: 6 }} onClick={() => navigator.clipboard?.writeText(value)}>
        {label}
      </button>
    </div>
  );
}
