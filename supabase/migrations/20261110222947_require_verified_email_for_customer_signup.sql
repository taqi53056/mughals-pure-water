-- Keep email ownership verification enabled for customer signup.
-- Supabase auto-populates email_confirmed_at on initial insert when Confirm email is disabled.
-- Reject that configuration for customer signups; admin approval remains a separate gate.
CREATE OR REPLACE FUNCTION public.handle_new_customer_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_name text;
  v_mobile text;
  v_address text;
BEGIN
  IF NEW.email_confirmed_at IS NOT NULL THEN
    RAISE EXCEPTION 'گاہک کی رجسٹریشن کے لیے ای میل کی تصدیق فعال ہونا ضروری ہے۔'
      USING errcode='22023';
  END IF;

  v_name := NULLIF(BTRIM(COALESCE(NEW.raw_user_meta_data->>'full_name','')), '');
  v_mobile := NULLIF(BTRIM(COALESCE(NEW.raw_user_meta_data->>'mobile','')), '');
  v_address := NULLIF(BTRIM(COALESCE(NEW.raw_user_meta_data->>'address','')), '');

  IF v_name IS NULL OR v_mobile IS NULL OR v_address IS NULL THEN
    RAISE EXCEPTION 'نام، موبائل نمبر اور پتہ لازمی ہیں۔'
      USING errcode='22023';
  END IF;

  INSERT INTO public.profiles(id,full_name,role)
  VALUES(NEW.id,v_name,'customer')
  ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.customers(name,mobile,address,auth_user_id,is_active)
  VALUES(v_name,v_mobile,v_address,NEW.id,false)
  ON CONFLICT(auth_user_id) DO NOTHING;

  RETURN NEW;
END;
$function$;
