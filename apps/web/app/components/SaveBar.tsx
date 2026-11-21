'use client';

import { useEffect, useState } from 'react';

/** Sticky button (gold unless `navy`) that submits a form elsewhere on the page (`form` attribute) and mirrors its pending state. */
export function SaveBar({ formId, label, navy }: { formId: string; label: string; navy?: boolean }) {
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
      <button type="submit" className={navy ? undefined : 'btn-gold'} form={formId} disabled={pending} aria-busy={pending}>
        {pending ? '…' : label}
      </button>
    </div>
  );
}
