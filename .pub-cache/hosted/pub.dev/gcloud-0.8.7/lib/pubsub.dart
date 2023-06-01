// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library gcloud.pubsub;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/pubsub/v1.dart' as pubsub;
import 'package:http/http.dart' as http;

import 'common.dart';
import 'service_scope.dart' as ss;
import 'src/common_utils.dart';

export 'common.dart';

part 'src/pubsub_impl.dart';

const Symbol _pubsubKey = #gcloud.pubsub;

/// Access the [PubSub] object available in the current service scope.
///
/// The returned object will be the one which was previously registered with
/// [registerPubSubService] within the current (or a parent) service scope.
///
/// Accessing this getter outside of a service scope will result in an error.
/// See the `package:gcloud/service_scope.dart` library for more information.
PubSub get pubsubService => ss.lookup(_pubsubKey) as PubSub;

/// Registers the [pubsub] object within the current service scope.
///
/// The provided `pubsub` object will be avilable via the top-level
/// `pubsubService` getter.
///
/// Calling this function outside of a service scope will result in an error.
/// Calling this function more than once inside the same service scope is not
/// allowed.
void registerPubSubService(PubSub pubsub) {
  ss.register(_pubsubKey, pubsub);
}

/// A Cloud Pub/Sub client.
///
/// Connects to the Cloud Pub/Sub service and gives access to its operations.
///
/// Google Cloud Pub/Sub is a reliable, many-to-many, asynchronous messaging
/// service from Google Cloud Platform. A detailed overview is available on
/// [Pub/Sub docs](https://developers.google.com/pubsub/overview).
///
/// To access Pub/Sub, an authenticate HTTP client is required. This client
/// should as a minimum provide access to the scopes `PubSub.Scopes`.
///
/// The following example shows how to access Pub/Sub using a service account
/// and pull a message from a subscription.
///
///     import 'package:http/http.dart' as http;
///     import 'package:googleapis_auth/auth_io.dart' as auth;
///     import 'package:gcloud/pubsub.dart';
///
///     Future<http.Client> createClient() {
///       // Service account credentials retrieved from Cloud Console.
///       String creds =
///           r'''
///           {
///             "private_key_id": ...,
///             "private_key": ...,
///             "client_email": ...,
///             "client_id": ...,
///             "type": "service_account"
///           }''';
///       return auth.clientViaServiceAccount(
///           new auth.ServiceAccountCredentials.fromJson(creds),
///           PubSub.Scopes);
///     }
///
///     main() {
///       var project = 'my-project';
///       var client;
///       var pubsub;
///       createClient().then((c) {
///         client = c;
///         pubsub = new PubSub(client, project);
///         return pubsub.lookupSubscription('my-subscription');
///       })
///       .then((Subscription subscription) => subscription.pull())
///       .then((PullEvent event) => print('Message ${event.message.asString}'))
///       .whenComplete(() => client.close());
///     }
///
/// When working with topics and subscriptions they are referred to using
/// names. These names can be either relative names or absolute names.
///
/// An absolute name of a topic starts with `projects/` and has the form:
///
///     projects/<project-id>/topics/<relative-name>
///
/// When a relative topic name is used, its absolute name is generated by
/// pre-pending `projects/<project-id>/topics/`, where `<project-id>` is the
/// project id passed to the constructor.
///
/// An absolute name of a subscription starts with `projects/` and has the
/// form:
///
///     projects/<project-id>/subscriptions/<relative-name>
///
/// When a relative subscription name is used, its absolute name is
/// generated by pre-pending `projects/<project-id>/subscriptions/`, where
/// `<project-id>` is the project id passed to the constructor.
///
abstract class PubSub {
  /// List of required OAuth2 scopes for Pub/Sub operation.
  // ignore: constant_identifier_names
  static const SCOPES = [pubsub.PubsubApi.pubsubScope];

  /// Access Pub/Sub using an authenticated client.
  ///
  /// The [client] is an authenticated HTTP client. This client must
  /// provide access to at least the scopes in `PubSub.Scopes`.
  ///
  /// The [project] is the name of the Google Cloud project.
  ///
  /// Returs an object providing access to Pub/Sub. The passed-in [client] will
  /// not be closed automatically. The caller is responsible for closing it.
  factory PubSub(http.Client client, String project) {
    var emulator = Platform.environment['PUBSUB_EMULATOR_HOST'];
    return emulator == null
        ? _PubSubImpl(client, project)
        : _PubSubImpl.rootUrl(client, project, 'http://$emulator/');
  }

  /// The name of the project.
  String get project;

  /// Create a new topic named [name].
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with the newly created topic.
  Future<Topic> createTopic(String name);

  /// Delete topic named [name].
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with `null` when the operation
  /// is finished.
  Future deleteTopic(String name);

  /// Look up topic named [name].
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with the topic.
  Future<Topic> lookupTopic(String name);

  /// Lists all topics.
  ///
  /// Returns a `Stream` of topics.
  Stream<Topic> listTopics();

  /// Start paging through all topics.
  ///
  /// The maximum number of topics in each page is specified in [pageSize].
  ///
  /// Returns a `Future` which completes with a `Page` object holding the
  /// first page. Use the `Page` object to move to the next page of topics.
  Future<Page<Topic>> pageTopics({int pageSize = 50});

  /// Create a new subscription named [name] listening on topic [topic].
  ///
  /// If [endpoint] is passed this will create a push subscription.
  ///
  /// Otherwise this will create a pull subscription.
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with the newly created subscription.
  Future<Subscription> createSubscription(String name, String topic,
      {Uri endpoint});

  /// Delete subscription named [name].
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with the subscription.
  Future deleteSubscription(String name);

  /// Lookup subscription with named [name].
  ///
  /// The [name] can be either an absolute name or a relative name.
  ///
  /// Returns a `Future` which completes with the subscription.
  Future<Subscription> lookupSubscription(String name);

  /// List subscriptions.
  ///
  /// If [query] is passed this will list all subscriptions matching the query.
  ///
  /// Otherwise this will list all subscriptions.
  ///
  /// The only supported query string is the name of a topic. If a name of a
  /// topic is passed as [query], this will list all subscriptions on that
  /// topic.
  ///
  /// Returns a `Stream` of subscriptions.
  Stream<Subscription> listSubscriptions([String query]);

  /// Start paging through subscriptions.
  ///
  /// If [topic] is passed this will list all subscriptions to that topic.
  ///
  /// Otherwise this will list all subscriptions.
  ///
  /// The maximum number of subscriptions in each page is specified in
  /// [pageSize]
  ///
  /// Returns a `Future` which completes with a `Page` object holding the
  /// first page. Use the `Page` object to move to the next page of
  /// subscriptions.
  Future<Page<Subscription>> pageSubscriptions(
      {String topic, int pageSize = 50});
}

/// A Pub/Sub topic.
///
/// A topic is used by a publisher to publish (send) messages.
abstract class Topic {
  /// The relative name of this topic.
  String get name;

  /// The name of the project for this topic.
  String get project;

  /// The absolute name of this topic.
  String get absoluteName;

  /// Delete this topic.
  ///
  /// Returns a `Future` which completes with `null` when the operation
  /// is finished.
  Future delete();

  /// Publish a message.
  ///
  /// Returns a `Future` which completes with `null` when the operation
  /// is finished.
  Future publish(Message message);

  /// Publish a string as a message.
  ///
  /// The message will get the attributes specified in [attributes].
  ///
  /// The [attributes] are passed together with the message to the receiver.
  ///
  /// Returns a `Future` which completes with `null` when the operation
  /// is finished.
  Future publishString(String message, {Map<String, String> attributes});

  /// Publish bytes as a message.
  ///
  /// The message will get the attributes specified in [attributes].
  ///
  /// The [attributes] are passed together with the message to the receiver.
  ///
  /// Returns a `Future` which completes with `null` when the operation
  /// is finished.
  Future publishBytes(List<int> message, {Map<String, String> attributes});
}

/// A Pub/Sub subscription
///
/// A subscription is used to receive messages. A subscriber application
/// create a subscription on a topic to receive messages from it.
///
/// Subscriptions can be either pull subscriptions or push subscriptions.
///
/// For a pull subscription the receiver calls the `Subscription.pull`
/// method on the subscription object to get the next message.
///
/// For a push subscription a HTTPS endpoint is configured. This endpoint get
/// POST requests with the messages.
abstract class Subscription {
  /// The relative name of this subscription.
  String get name;

  /// The name of the project for this subscription.
  String get project;

  /// The absolute name of this subscription.
  String get absoluteName;

  /// The topic subscribed to.
  Topic get topic;

  /// Whether this is a push subscription.
  ///
  /// A push subscription is configured with an endpoint URI, and messages
  /// are automatically sent to this endpoint without needing to call [pull].
  bool get isPush;

  /// Whether this is a pull subscription.
  ///
  /// A subscription without a configured endpoint URI is a pull subscription.
  /// Messages are not delivered automatically, but must instead be requested
  /// using [pull].
  bool get isPull;

  /// The URI for the push endpoint.
  ///
  /// If this is a pull subscription this is `null`.
  Uri? get endpoint;

  /// Update the push configuration with a new endpoint.
  ///
  /// if [endpoint] is `null`, the subscription stops delivering messages
  /// automatically, and becomes a pull subscription, if it isn't already.
  ///
  /// If [endpoint] is not `null`, the subscription will be a push
  /// subscription, if it wasn't already, and Pub/Sub will start automatically
  /// delivering message to the endpoint URI.
  ///
  /// Returns a `Future` which completes when the operation completes.
  Future updatePushConfiguration(Uri endpoint);

  /// Delete this subscription.
  ///
  /// Returns a `Future` which completes when the operation completes.
  Future delete();

  /// Pull a message from the subscription.
  ///
  /// If `wait` is `true` (the default), the method will wait for a message
  /// to become available, and will then complete the `Future` with a
  /// `PullEvent` containing the message.
  ///
  /// If [wait] is `false`, the method will complete the returned `Future`
  /// with `null` if it finds that there are no messages available.
  Future<PullEvent?> pull({bool wait = true});
}

/// The content of a Pub/Sub message.
///
/// All Pub/Sub messages consist of a body of binary data and has an optional
/// set of attributes (key-value pairs) associated with it.
///
/// A `Message` contains the message body a list of bytes. The message body can
/// be read and written as a String, in which case the string is converted to
/// or from UTF-8 automatically.
abstract class Message {
  /// Creates a new message with a String for the body. The String will
  /// be UTF-8 encoded to create the actual binary body for the message.
  ///
  /// Message attributes can be passed in the [attributes] map.
  factory Message.withString(String message, {Map<String, String> attributes}) =
      _MessageImpl.withString;

  /// Creates a new message with a binary body.
  ///
  /// Message attributes can be passed in the [attributes] Map.
  factory Message.withBytes(List<int> message,
      {Map<String, String> attributes}) = _MessageImpl.withBytes;

  /// The message body as a String.
  ///
  /// The binary body is decoded into a String using an UTF-8 decoder.
  ///
  /// If the body is not UTF-8 encoded use the [asBytes] getter and manually
  /// apply the correct decoding.
  String get asString;

  /// The message body as bytes.
  List<int> get asBytes;

  /// The attributes for this message.
  Map<String, String> get attributes;
}

/// A Pub/Sub pull event.
///
/// Instances of this class are returned when pulling messages with
/// [Subscription.pull].
abstract class PullEvent {
  /// The message content.
  Message get message;

  /// Acknowledge reception of this message.
  ///
  /// Returns a `Future` which completes with `null` when the acknowledge has
  /// been processed.
  Future acknowledge();
}

/// Pub/Sub push event.
///
/// This class can be used in a HTTP server for decoding messages pushed to
/// an endpoint.
///
/// When a message is received on a push endpoint use the [PushEvent.fromJson]
/// constructor with the HTTP body to decode the received message.
///
/// E.g. with a `dart:io` HTTP handler:
///
///     void pushHandler(HttpRequest request) {
///       // Decode the JSON body.
///       request.transform(UTF8.decoder).join('').then((body) {
///         // Decode the JSON into a push message.
///         var message = new PushMessage.fromJson(body)
///
///         // Process the message...
///
///         // Respond with status code 20X to acknowledge the message.
///         response.statusCode = statusCode;
///         response.close();
///       });
///     }
////
abstract class PushEvent {
  /// The message content.
  Message get message;

  /// The absolute name of the subscription.
  String get subscriptionName;

  /// Create a `PushMessage` from JSON received on a Pub/Sub push endpoint.
  factory PushEvent.fromJson(String json) = _PushEventImpl.fromJson;
}
