class_name Downloader
extends RefCounted

## The render layer's only socket.
##
## `TC-OFF-003` holds that no runtime source under `res://core` or
## `res://protocols` opens a network path, so `PackageLoader.import_url` takes
## bytes and a digest and never a URL it can dial itself. This file is the other
## half of that arrangement: it fetches the bytes and hands them over, and it
## keeps the one place where a timeout and a status code are decided.
##
## The fetch is a coroutine on purpose. `HTTPRequest` reports completion through
## a signal, and `import_url` runs the fetch synchronously through a `Callable`,
## so the coroutine is awaited here and the caller receives a `PackedByteArray`
## or an empty one. An empty answer is what `V-01` describes: `import_url` says
## `could not download the package from <url>` and the screen shows that.

const TIMEOUT_MS := 15000


static func fetch(host: Node, url: String) -> PackedByteArray:
	## Fetches a package from `url`, or returns empty bytes when the request did
	## not finish, did not answer 200, or returned nothing. Errors are flattened
	## to "no bytes" because `import_url` already has a message for that case and
	## a second vocabulary would give the player two shapes of the same failure.
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_MS
	host.add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return PackedByteArray()
	var answer: Array = await request.request_completed
	request.queue_free()
	var result_code := int(answer[0])
	var status := int(answer[1])
	var body: PackedByteArray = answer[3]
	if result_code != HTTPRequest.RESULT_SUCCESS or status != 200:
		return PackedByteArray()
	return body
