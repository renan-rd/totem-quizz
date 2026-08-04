-- Allow WhatsApp and Slack as agent channels
alter type public.agent_channel add value if not exists 'whatsapp';
alter type public.agent_channel add value if not exists 'slack';
