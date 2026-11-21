'use client';

import { useEffect, useState } from 'react';

/** Sticky gold button that submits a form elsewhere on the page (`form` attribute) and mirrors its pending state. */
export function SaveBar({ formId, label }: { formId: string; label: string }) {
  const [pending, setPending] = useState(false);
  useEffect(() => {
    const form = document.getElementById(formId);
    if (!form) return;
    const sync = () => setPending(form.getAttribute('data-pending') === 'true');
    const mo = new MutationObserver(sync);
    mo.observe(form, { attributes: true, attributeFilter: ['data-pending'] });
    sync();
    return () => mo.disconnect();
  }, [formId]);
  return (
    <div className="save-bar">
      <button type="submit" className="btn-gold" form={formId} disabled={pending} aria-busy={pending}>
        {pending ? '…' : label}
      </button>
    </div>
  );
}
