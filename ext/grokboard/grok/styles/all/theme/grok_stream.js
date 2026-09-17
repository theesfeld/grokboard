(function ($) {
	'use strict';

	var $cfg = $('#grokboard-config');
	if (!$cfg.length || !$cfg.data('pending')) {
		return;
	}

	var streamUrl = $cfg.data('stream');
	var queueId = $cfg.data('queue');
	var postId = $cfg.data('post');
	var topicId = $cfg.data('topic');
	var es = null;

	function lastPostList() {
		return $('#page-body, .page-body').find('.post').last();
	}

	function injectSkeleton() {
		if ($('#pGrokLive').length) {
			return $('#pGrokLive');
		}
		var $last = lastPostList();
		var $post = $('<div id="pGrokLive" class="post bg2 has-profile grokboard-live">' +
			'<div class="inner">' +
			'<dl class="postprofile" id="profileGrokLive">' +
			'<dt class="has-profile-rank no-avatar"><div class="avatar-container"></div>' +
			'<a class="username">Grok</a></dt>' +
			'<dd class="profile-rank">xAI</dd>' +
			'<dd><strong>Posts:</strong> streaming</dd>' +
			'</dl>' +
			'<div class="postbody">' +
			'<div class="h3">Re: …</div>' +
			'<p class="author"><span class="imageset icon_post_target"></span> by <strong>Grok</strong> » right now</p>' +
			'<div class="content grokboard-cursor" id="grok-stream-body"></div>' +
			'</div></div></div>');
		if ($last.length) {
			$last.after($post);
		} else {
			$('#page-body, .page-body').append($post);
		}
		return $post;
	}

	function start() {
		var $post = injectSkeleton();
		var $body = $post.find('#grok-stream-body');
		var url = streamUrl + (streamUrl.indexOf('?') >= 0 ? '&' : '?') +
			'queue_id=' + encodeURIComponent(queueId) +
			'&t=' + encodeURIComponent(topicId) +
			'&p=' + encodeURIComponent(postId);

		if (typeof EventSource === 'undefined') {
			$body.text('This browser cannot stream. Reload in a minute.');
			return;
		}

		es = new EventSource(url);

		es.addEventListener('token', function (ev) {
			var data = {};
			try { data = JSON.parse(ev.data); } catch (e) { return; }
			if (data.t) {
				$body.append(document.createTextNode(data.t));
				if (window.scrollY + window.innerHeight > document.body.scrollHeight - 80) {
					window.scrollTo(0, document.body.scrollHeight);
				}
			}
		});

		es.addEventListener('tool', function (ev) {
			var data = {};
			try { data = JSON.parse(ev.data); } catch (e) { return; }
			var line = (data.name || 'tool') + (data.status ? ' (' + data.status + ')' : '');
			$body.append($('<div class="grokboard-tool"/>').text(line));
		});

		es.addEventListener('done', function (ev) {
			var data = {};
			try { data = JSON.parse(ev.data); } catch (e) { data = {}; }
			es.close();
			$body.removeClass('grokboard-cursor');
			if (data.html) {
				$body.html(data.html);
			}
			$post.removeClass('grokboard-live');
			window.setTimeout(function () {
				window.location.reload();
			}, 400);
		});

		es.addEventListener('error', function (ev) {
			var data = {};
			try { data = JSON.parse(ev.data); } catch (e) { data = {}; }
			$body.removeClass('grokboard-cursor');
			$body.empty();
			$body.append($('<p class="grokboard-error"/>').text(data.message || 'Grok dropped the connection.'));
			if (es) { es.close(); }
		});

		es.onerror = function () {
			if (es && es.readyState === EventSource.CLOSED) {
				$body.removeClass('grokboard-cursor');
			}
		};
	}

	$(start);
})(jQuery);
