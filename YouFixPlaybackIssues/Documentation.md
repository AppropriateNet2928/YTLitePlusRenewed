# What is this about?
This is about how a request made by endpoints like /browse may actually work. This regards the beginning of it, what it does/goes through step by step and documented results. This theory is based on the latest observed behavior of
my tweak, YouFixPlaybackIssues

# What is this "request"?

This request is, for example, like u would make a request to get what u need in return. In this case, for example, requests regarding the /browse endpoint with request headers and etc
in order to get back from Google's servers I think things like browseID, continuation etc.

This kind of "request" has more steps that it goes through ion the Youtube application before it gets to the server:

# What are the steps that a request can go through?

Well the "request" goes through a few multiple steps, which is more of a "route". 

The "request's route" would be, conceptually:

1) NSMutableRequest/NSRequest -> NSURLSession:

Here is where the request is in the earliest state: It is made and given to NSURLSession to get it prepped and send it. This is the earliest point possible I think where u can modify
the request in order to send the request u modified to have ur custom headers, like my tweak does. The request is most likely JSON.

2) NSURLSessionDataTask/NSURLSessionTask -> GTMSessionFetcher (probably):

This is the point where the request was made and sent forward; The point where u will be once able to modify it comes next. Here u can't modify it I THINK bc the request is processing
in order to be sent forward;

3) GTMSessionFetcher -> GTMSessionFetcherSessionDelegateDispatcher (most likely):

Here is the point where u can modify the request once more; This class is most likely boring open the request, checking its contents to make sure the request is right and it has all
the headers and it may rewrite it to protobuf or modify it:

This class and GTMSessionFetcherSessionDelegateDispatcher most likely have a built in protobuf parser/decoder/parser etc and can modify the requests. This is most likely a security patch
made by Google in YouTube to prevent god knows what. Now this class has methods that allow us to tell these two classes that we want to eliminate the headers in the original request and
replace them with the headers we give it. These two classes can automatically do it thanks to the possible capability to write directly in x-protobuf.

If u force the Content-type to be sth else than application/x-protobuf (the error is for when the content type is application/json or application/protobuf+json [ProtoJSON], u get error 400 Bad Request, with the response body being:

```json
{
  "error": {
    "message": "Invalid JSON payload received. Expected a value.\n \u0006\n \u0003\n\u0002en\u0012\u0002ROb\u0005Applej\n ^",
    "status": "INVALID_ARGUMENT",
    "code": 400
  }
}
```

See the error? It says it expects a VALUE than text that, is MOST LIKELY binary protobuf, further proving my point :))

4) GTMSessionFetcherSessionDelegateDispatcher -> Google's servers

This is the step where the dispatcher makes the last check on the request, ALSO having the ability to modify it, and redirects it/sends it to Google's servers.


# What would be the conclusion?

Well the conclusion would be that this THEORY may have points where it is correct or have points where it's wrong and I only present this as a theory, not as a factual truth. This may
get more documentation over time as this behavior will most likely analyses better.






