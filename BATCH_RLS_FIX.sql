-- Allow authenticated admins to manage inventory batches.
-- Run once in Supabase SQL Editor.
CREATE POLICY "Admins can insert batches"
ON public.batches
FOR INSERT
TO authenticated
WITH CHECK ((auth.jwt()->'app_metadata'->>'role') = 'admin');

CREATE POLICY "Admins can update batches"
ON public.batches
FOR UPDATE
TO authenticated
USING ((auth.jwt()->'app_metadata'->>'role') = 'admin')
WITH CHECK ((auth.jwt()->'app_metadata'->>'role') = 'admin');

CREATE POLICY "Admins can delete batches"
ON public.batches
FOR DELETE
TO authenticated
USING ((auth.jwt()->'app_metadata'->>'role') = 'admin');

CREATE POLICY "Admins can read batches"
ON public.batches
FOR SELECT
TO authenticated
USING ((auth.jwt()->'app_metadata'->>'role') = 'admin');
