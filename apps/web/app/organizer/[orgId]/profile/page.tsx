import Link from 'next/link';
import { ActionForm } from '../../../components/ActionForm';
import { PageHeader } from '../../../components/PageHeader';
import { api } from '../../../lib/api';
import { t } from '../../../lib/i18n';
import { saveProfileAction } from '../../actions';

export const dynamic = 'force-dynamic';

interface Profile {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  descriptionMy: string | null;
  website: string | null;
  facebookUrl: string | null;
  contactEmail: string | null;
  contactPhone: string | null;
  showContact: boolean;
  logoUrl: string | null;
}

export default async function ProfilePage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const [tr, p] = await Promise.all([t(), api<Profile>(`/organizations/${orgId}/profile`)]);
  return (
    <>
      <PageHeader breadcrumb={<Link href={`/organizer/${orgId}`}>← {p.name}</Link>} title={tr.profile} subtitle={tr.profileHint} />
      <div className="card">
        <ActionForm action={saveProfileAction} submitLabel={tr.save} variant="gold" okText={{ saved: tr.saved }}>
          <input type="hidden" name="orgId" value={orgId} />
          <div className="field">
            <label>{tr.logo}</label>
            {p.logoUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={p.logoUrl} alt="" className="thumb logo" style={{ marginBottom: 6 }} />
            )}
            <input name="logo" type="file" accept="image/jpeg,image/png,image/webp" />
          </div>
          <div className="grid">
            <div className="field"><label>{tr.description} ({tr.en})</label><textarea name="description" defaultValue={p.description ?? ''} /></div>
            <div className="field"><label>{tr.description} ({tr.myLabel})</label><textarea name="descriptionMy" lang="my" defaultValue={p.descriptionMy ?? ''} /></div>
            <div className="field"><label>{tr.website}</label><input name="website" type="url" placeholder="https://" defaultValue={p.website ?? ''} /></div>
            <div className="field"><label>{tr.facebook}</label><input name="facebookUrl" type="url" placeholder="https://facebook.com/…" defaultValue={p.facebookUrl ?? ''} /></div>
            <div className="field"><label>{tr.email}</label><input name="contactEmail" type="email" defaultValue={p.contactEmail ?? ''} /></div>
            <div className="field"><label>{tr.phone}</label><input name="contactPhone" defaultValue={p.contactPhone ?? ''} /></div>
          </div>
          <div className="field">
            <label className="check">
              <input type="checkbox" name="showContact" defaultChecked={p.showContact} /> {tr.showContact}
            </label>
          </div>
        </ActionForm>
      </div>
    </>
  );
}
