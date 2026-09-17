<?php

namespace grokboard\grok\acp;

class main_module
{
	public $u_action;
	public $tpl_name;
	public $page_title;

	public function main($id, $mode)
	{
		global $phpbb_container, $request, $template, $user;

		$user->add_lang_ext('grokboard/grok', 'info_acp_grokboard');

		$this->tpl_name = 'acp_grokboard';
		$this->page_title = $user->lang('ACP_GROKBOARD');

		add_form_key('grokboard_grok_auth');

		/** @var \grokboard\grok\auth\cli $cli */
		$cli = $phpbb_container->get('grokboard.auth.cli');

		$notice = '';
		$error = '';

		if ($request->is_set_post('save_key'))
		{
			if (!check_form_key('grokboard_grok_auth'))
			{
				trigger_error('FORM_INVALID');
			}
			$key = $request->variable('api_key', '', true);
			$result = $cli->set_key($key);
			if (!empty($result['ok']) && !empty($result['authenticated']))
			{
				$notice = $user->lang('ACP_GROKBOARD_KEY_SAVED');
			}
			else
			{
				$error = $result['error'] ?? $user->lang('ACP_GROKBOARD_AUTH_FAILED');
			}
		}
		else if ($request->is_set_post('start_device'))
		{
			if (!check_form_key('grokboard_grok_auth'))
			{
				trigger_error('FORM_INVALID');
			}
			$result = $cli->device_start();
			if (empty($result['ok']) && empty($result['verification_url']) && empty($result['user_code']))
			{
				$error = $result['error'] ?? $user->lang('ACP_GROKBOARD_AUTH_FAILED');
			}
		}
		else if ($request->is_set_post('cancel_device'))
		{
			if (!check_form_key('grokboard_grok_auth'))
			{
				trigger_error('FORM_INVALID');
			}
			$cli->device_cancel();
			$notice = $user->lang('ACP_GROKBOARD_DEVICE_CANCELLED');
		}
		else if ($request->is_set_post('clear'))
		{
			if (!check_form_key('grokboard_grok_auth'))
			{
				trigger_error('FORM_INVALID');
			}
			$cli->clear();
			$notice = $user->lang('ACP_GROKBOARD_CLEARED');
		}

		$status = $cli->status();
		$device = $cli->device_status();
		if (($device['status'] ?? '') === 'idle' || ($device['status'] ?? '') === 'complete')
		{
			// keep status from status()
		}

		$hash = generate_link_hash('grok_auth');
		$helper = $phpbb_container->get('controller.helper');
		$auth_url = $helper->route('grokboard_auth', ['hash' => $hash]);

		$method = (string) ($status['method'] ?? 'none');
		$method_label = $user->lang('ACP_GROKBOARD_METHOD_NONE');
		if ($method === 'device')
		{
			$method_label = $user->lang('ACP_GROKBOARD_METHOD_DEVICE');
		}
		else if ($method === 'api_key')
		{
			$method_label = $user->lang('ACP_GROKBOARD_METHOD_KEY');
		}

		$template->assign_vars([
			'U_ACTION'					=> $this->u_action,
			'U_GROKBOARD_AUTH'			=> $auth_url,
			'S_GROK_AUTHENTICATED'		=> !empty($status['authenticated']),
			'GROK_AUTH_METHOD'			=> $method_label,
			'GROK_AUTH_EMAIL'			=> (string) ($status['email'] ?? ''),
			'GROK_DEVICE_STATUS'		=> (string) ($device['status'] ?? 'idle'),
			'GROK_DEVICE_URL'			=> (string) ($device['verification_url'] ?? ''),
			'GROK_DEVICE_CODE'			=> (string) ($device['user_code'] ?? ''),
			'GROK_NOTICE'				=> $notice,
			'GROK_ERROR'				=> $error,
			'L_ACP_GROKBOARD_WAITING'	=> $user->lang('ACP_GROKBOARD_WAITING'),
			'L_ACP_GROKBOARD_SIGNED_IN'	=> $user->lang('ACP_GROKBOARD_SIGNED_IN'),
			'L_ACP_GROKBOARD_AUTH_FAILED'	=> $user->lang('ACP_GROKBOARD_AUTH_FAILED'),
		]);
	}
}
