import Link from 'next/link';
import { ActionForm } from '../../../../components/ActionForm';
import { api } from '../../../../lib/api';
import { t } from '../../../../lib/i18n';
import type { CategoryDto } from '../../../../lib/types';
import { createEventAction } from '../../../actions';
import { EventFields } from '../../../EventFields';

export const dynamic = 'force-dynamic';

export default async function NewEventPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const [tr, categories] = await Promise.all([t(), api<CategoryDto[]>('/categories', { auth: false })]);
  return (
    <>
      <p><Link href={`/organizer/${orgId}`}>← {tr.events}</Link></p>
      <h1>{tr.newEvent}</h1>
      <div className="card">
        <ActionForm action={createEventAction} submitLabel={tr.create}>
          <input type="hidden" name="orgId" value={orgId} />
          <EventFields tr={tr} categories={categories} />
        </ActionForm>
      </div>
    </>
  );
}
