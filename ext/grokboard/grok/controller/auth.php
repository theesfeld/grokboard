<?php

namespace grokboard\grok\controller;

use Symfony\Component\HttpFoundation\JsonResponse;

class auth
{
	protected $auth;
	protected $request;
	protected $user;
	protected $cli;

	public function __construct(\phpbb\auth\auth $auth, \phpbb\request\request $request, \phpbb\user $user, \grokboard\grok\auth\cli $cli)
	{
		$this->auth = $auth;
		$this->request = $request;
		$this->user = $user;
		$this->cli = $cli;
	}

	public function handle()
	{
		if ($this->user->data['user_id'] == ANONYMOUS || !$this->auth->acl_get('a_board'))
		{
			return new JsonResponse(['ok' => false, 'error' => 'NOT_AUTHORISED'], 403);
		}

		$hash = $this->request->variable('hash', '');
		if (!check_link_hash($hash, 'grok_auth'))
		{
			return new JsonResponse(['ok' => false, 'error' => 'NOT_AUTHORISED'], 403);
		}

		$action = $this->request->variable('action', 'status');
		switch ($action)
		{
			case 'status':
				$result = $this->cli->status();
			break;

			case 'start_device':
				if ($this->request->server('REQUEST_METHOD') !== 'POST')
				{
					return new JsonResponse(['ok' => false, 'error' => 'POST required'], 405);
				}
				$result = $this->cli->device_start();
			break;

			case 'device_status':
				$result = $this->cli->device_status();
			break;

			case 'cancel_device':
				if ($this->request->server('REQUEST_METHOD') !== 'POST')
				{
					return new JsonResponse(['ok' => false, 'error' => 'POST required'], 405);
				}
				$result = $this->cli->device_cancel();
			break;

			case 'save_key':
				if ($this->request->server('REQUEST_METHOD') !== 'POST')
				{
					return new JsonResponse(['ok' => false, 'error' => 'POST required'], 405);
				}
				$key = $this->request->variable('api_key', '', true);
				$result = $this->cli->set_key($key);
			break;

			case 'clear':
				if ($this->request->server('REQUEST_METHOD') !== 'POST')
				{
					return new JsonResponse(['ok' => false, 'error' => 'POST required'], 405);
				}
				$result = $this->cli->clear();
			break;

			default:
				return new JsonResponse(['ok' => false, 'error' => 'unknown action'], 400);
		}

		return new JsonResponse($result);
	}
}
