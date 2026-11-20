import type { CategoryDto, EventDto } from '../lib/types';
import { pick, toLocalInput } from '../lib/i18n';

type Tr = Awaited<ReturnType<typeof import('../lib/i18n').t>>;

/** Inputs shared by the create and edit event forms (rendered inside an ActionForm). */
export function EventFields({ tr, categories, event }: { tr: Tr; categories: CategoryDto[]; event?: EventDto }) {
  const e = event;
  return (
    <>
      <div className="grid">
        <div className="field"><label>{tr.title}</label><input name="title" required minLength={3} defaultValue={e?.title} /></div>
        <div className="field"><label>{tr.titleMy}</label><input name="titleMy" lang="my" defaultValue={e?.titleMy ?? ''} /></div>
        <div className="field"><label>{tr.summary}</label><input name="summary" maxLength={300} defaultValue={e?.summary ?? ''} /></div>
        <div className="field"><label>{tr.summaryMy}</label><input name="summaryMy" lang="my" maxLength={300} defaultValue={e?.summaryMy ?? ''} /></div>
      </div>
      <div className="grid">
        <div className="field"><label>{tr.descriptionEn}</label><textarea name="description" defaultValue={e?.description ?? ''} /></div>
        <div className="field"><label>{tr.descriptionMy}</label><textarea name="descriptionMy" lang="my" defaultValue={e?.descriptionMy ?? ''} /></div>
      </div>
      <div className="grid">
        <div className="field">
          <label>{tr.category}</label>
          <select name="categoryId" required defaultValue={e?.category.id ?? ''}>
            <option value="" disabled>—</option>
            {categories.map((c) => (
              <optgroup key={c.id} label={pick(tr.lang, c.nameEn, c.nameMy)}>
                {c.children.map((s) => <option key={s.id} value={s.id}>{pick(tr.lang, s.nameEn, s.nameMy)}</option>)}
              </optgroup>
            ))}
          </select>
        </div>
        <div className="field">
          <label>{tr.format}</label>
          <select name="format" defaultValue={e?.format ?? 'IN_PERSON'}>
            {['IN_PERSON', 'ONLINE', 'HYBRID'].map((f) => <option key={f} value={f}>{tr.formats[f]}</option>)}
          </select>
        </div>
        <div className="field">
          <label>{tr.visibility}</label>
          <select name="visibility" defaultValue={e?.visibility ?? 'PUBLIC'}>
            {['PUBLIC', 'PRIVATE'].map((v) => <option key={v} value={v}>{tr.visibilities[v]}</option>)}
          </select>
        </div>
        <div className="field"><label>{tr.startsAt}</label><input name="startsAt" type="datetime-local" required defaultValue={e ? toLocalInput(e.startsAt) : ''} /></div>
        <div className="field"><label>{tr.endsAt}</label><input name="endsAt" type="datetime-local" required defaultValue={e ? toLocalInput(e.endsAt) : ''} /></div>
      </div>
      <h2>{tr.venue}</h2>
      <div className="grid">
        <div className="field"><label>{tr.venueName}</label><input name="venueName" defaultValue={e?.venue?.name ?? ''} /></div>
        <div className="field"><label>{tr.venueNameMy}</label><input name="venueNameMy" lang="my" defaultValue={e?.venue?.nameMy ?? ''} /></div>
        <div className="field"><label>{tr.address}</label><input name="address" defaultValue={e?.venue?.address ?? ''} /></div>
        <div className="field"><label>{tr.city}</label><input name="city" defaultValue={e?.venue?.city ?? 'Yangon'} /></div>
        <div className="field"><label>{tr.mapUrl}</label><input name="mapUrl" type="url" placeholder="https://maps.app.goo.gl/…" defaultValue={e?.venue?.mapUrl ?? ''} /></div>
        <div className="field"><label>{tr.latitude}</label><input name="latitude" inputMode="decimal" defaultValue={e?.venue?.latitude ?? ''} /></div>
        <div className="field"><label>{tr.longitude}</label><input name="longitude" inputMode="decimal" defaultValue={e?.venue?.longitude ?? ''} /></div>
      </div>
      <div className="grid">
        <div className="field"><label>{tr.directions} ({tr.en})</label><textarea name="directions" defaultValue={e?.venue?.directions ?? ''} style={{ minHeight: 70 }} /></div>
        <div className="field"><label>{tr.directions} ({tr.myLabel})</label><textarea name="directionsMy" lang="my" defaultValue={e?.venue?.directionsMy ?? ''} style={{ minHeight: 70 }} /></div>
      </div>
      <h2>{tr.practicalInfo}</h2>
      <div className="grid">
        <div className="field"><label>{tr.ageMin}</label><input name="ageMin" type="number" min={0} max={99} defaultValue={e?.ageMin ?? ''} /></div>
        {(
          [
            ['dressCode', tr.dressCode],
            ['languages', tr.languagesField],
            ['parking', tr.parking],
            ['accessibility', tr.accessibility],
            ['whatToBring', tr.whatToBring],
          ] as const
        ).map(([k, label]) => (
          <div key={k} style={{ display: 'contents' }}>
            <div className="field"><label>{label} ({tr.en})</label><input name={k} defaultValue={(e?.[k] as string | null) ?? ''} /></div>
            <div className="field"><label>{label} ({tr.myLabel})</label><input name={`${k}My`} lang="my" defaultValue={(e?.[`${k}My`] as string | null) ?? ''} /></div>
          </div>
        ))}
      </div>
      <div className="grid">
        {(
          [
            ['terms', tr.termsField],
            ['refundPolicy', tr.refundPolicy],
          ] as const
        ).map(([k, label]) => (
          <div key={k} style={{ display: 'contents' }}>
            <div className="field"><label>{label} ({tr.en})</label><textarea name={k} defaultValue={(e?.[k] as string | null) ?? ''} /></div>
            <div className="field"><label>{label} ({tr.myLabel})</label><textarea name={`${k}My`} lang="my" defaultValue={(e?.[`${k}My`] as string | null) ?? ''} /></div>
          </div>
        ))}
      </div>
      <div className="grid">
        <div className="field">
          <input type="hidden" name="transferSettings" value="1" />
          <label className="check"><input type="checkbox" name="transfersEnabled" defaultChecked={e?.transfersEnabled ?? true} /> {tr.transfersEnabled}</label>
          <small className="muted">{tr.transfersHint}</small>
        </div>
        <div className="field">
          <label>{tr.transferCutoff}</label>
          <input name="transferCutoffHours" type="number" min={0} max={168} defaultValue={e?.transferCutoffHours ?? 2} />
        </div>
      </div>
      <div className="field">
        <label>{tr.coverImage}</label>
        {e?.coverImageUrl && <img className="cover" src={e.coverImageUrl} alt="" style={{ marginBottom: 8 }} />}
        <input name="cover" type="file" accept="image/jpeg,image/png,image/webp" />
      </div>
    </>
  );
}
