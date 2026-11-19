'use client';

import { useState } from 'react';

export interface FieldDef {
  name: string;
  label: string;
  type?: 'text' | 'textarea' | 'datetime' | 'image';
  required?: boolean;
  lang?: 'my';
  /** For image fields: the row key holding the current image URL (for the preview). */
  previewKey?: string;
}

type Row = Record<string, string>;

/**
 * Editable list of rows (schedule items, performers, gallery images, FAQ). Rows are submitted as JSON in
 * the hidden "items" input; image fields are submitted as files named `file_<row>_<field>`.
 */
export function ListEditor({
  fields,
  initial,
  labels,
}: {
  fields: FieldDef[];
  initial: Row[];
  labels: { add: string; remove: string; up: string; empty: string };
}) {
  const blank = (): Row => Object.fromEntries(fields.map((f) => [f.name, '']));
  const [rows, setRows] = useState<Row[]>(initial);
  const update = (i: number, k: string, v: string) => setRows((r) => r.map((row, j) => (j === i ? { ...row, [k]: v } : row)));
  const move = (i: number) => setRows((r) => (i === 0 ? r : [...r.slice(0, i - 1), r[i], r[i - 1], ...r.slice(i + 1)]));
  const serialized = rows.map((row) => Object.fromEntries(Object.entries(row).filter(([k]) => !k.startsWith('_'))));

  return (
    <div>
      <input type="hidden" name="items" value={JSON.stringify(serialized)} />
      {rows.length === 0 && <p className="muted">{labels.empty}</p>}
      {rows.map((row, i) => (
        <div key={i} className="card" style={{ padding: 12, background: 'var(--bg)' }}>
          <div className="grid">
            {fields.map((f) => (
              <div className="field" key={f.name} style={f.type === 'textarea' ? { gridColumn: '1 / -1' } : undefined}>
                <label>{f.label}</label>
                {f.type === 'textarea' ? (
                  <textarea lang={f.lang} value={row[f.name] ?? ''} onChange={(e) => update(i, f.name, e.target.value)} style={{ minHeight: 70 }} />
                ) : f.type === 'image' ? (
                  <>
                    {row[f.previewKey ?? '_url'] && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={row[f.previewKey ?? '_url']} alt="" style={{ height: 64, borderRadius: 8, display: 'block', marginBottom: 6 }} />
                    )}
                    <input type="file" name={`file_${i}_${f.name}`} accept="image/jpeg,image/png,image/webp" />
                  </>
                ) : (
                  <input
                    type={f.type === 'datetime' ? 'datetime-local' : 'text'}
                    lang={f.lang}
                    required={f.required}
                    value={row[f.name] ?? ''}
                    onChange={(e) => update(i, f.name, e.target.value)}
                  />
                )}
              </div>
            ))}
          </div>
          <div className="row">
            {i > 0 && (
              <button type="button" className="secondary" onClick={() => move(i)}>
                ↑ {labels.up}
              </button>
            )}
            <button type="button" className="secondary" onClick={() => setRows((r) => r.filter((_, j) => j !== i))}>
              {labels.remove}
            </button>
          </div>
        </div>
      ))}
      <button type="button" className="secondary" onClick={() => setRows((r) => [...r, blank()])} style={{ marginBottom: 12 }}>
        + {labels.add}
      </button>
    </div>
  );
}
