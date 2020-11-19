//
// MessageEventHandler.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift
import TigaseSwiftOMEMO
import os

class MessageEventHandler: XmppServiceEventHandler {

    public static let OMEMO_AVAILABILITY_CHANGED = Notification.Name(rawValue: "OMEMOAvailabilityChanged");

    static func prepareBody(message: Message, forAccount account: BareJID) -> (String?, MessageEncryption, String?) {
        var encryption: MessageEncryption = .none;
        var fingerprint: String? = nil;

        guard (message.type ?? .chat) != .error else {
            guard let body = message.body else {
                if let delivery = message.messageDelivery {
                    switch delivery {
                    case .received(_):
                        // if our message delivery confirmation is not delivered just drop this info
                        return (nil, encryption, nil);
                    default:
                        break;
                    }
                }
                return (message.to?.resource == nil ? nil : "", encryption, nil);
            }
            return (body, encryption, nil);
        }

        var encryptionErrorBody: String?;
        if let omemoModule: OMEMOModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(OMEMOModule.ID) {
            switch omemoModule.decode(message: message) {
            case .successMessage(_, let keyFingerprint):
                encryption = .decrypted;
                fingerprint = keyFingerprint
                break;
            case .successTransportKey(_, _):
                print("got transport key with key and iv!");
            case .failure(let error):
                switch error {
                case .invalidMessage:
                    encryptionErrorBody = "Message was not encrypted for this device.";
                    encryption = .notForThisDevice;
                case .duplicateMessage:
                    // message is a duplicate and was processed before
                    return (nil, .none, nil);
                case .notEncrypted:
                    encryption = .none;
                default:
                    encryptionErrorBody = "Message decryption failed!";
                    encryption = .decryptionFailed;
                }
                break;
            }
        }

        guard let body = message.body ?? message.oob ?? encryptionErrorBody else {
            return (nil, encryption, nil);
        }
        return (body, encryption, fingerprint);
    }

    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, DiscoveryModule.AccountFeaturesReceivedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, MessageArchiveManagementModule.ArchivedMessageReceivedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, OMEMOModule.AvailabilityChangedEvent.TYPE];

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.CHANGED, object: nil);
    }

    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings else {
            return;
        }

        switch setting {
        case .enableMessageCarbons:
            XmppService.instance.clients.values.filter { (client) -> Bool in
                return client.state == .connected
                }.forEach { client in
                    guard let mcModule: MessageCarbonsModule = client.modulesManager.getModule(MessageCarbonsModule.ID), mcModule.isAvailable else {
                        return;
                    }
                    if setting.bool() {
                        mcModule.enable();
                    } else {
                        mcModule.disable();
                    }
            }
        default:
            break;
        }
    }

    func handle(event: Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            guard e.message.from != nil, let account = e.sessionObject.userBareJid else {
                return;
            }

            DBChatHistoryStore.instance.append(for: e.chat as! Conversation, message: e.message, source: .stream);
        case let e as MessageDeliveryReceiptsModule.ReceiptEvent:
            guard let from = e.message.from, let account = e.sessionObject.userBareJid else {
                return;
            }
            
            var conversation: ConversationKey?;
            if e.message.findChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") != nil {
                // this is for MUC-PM only!!
                conversation = DBChatStore.instance.conversation(for: account, with: from);
            } else {
                conversation = DBChatStore.instance.conversation(for: account, with: from.withoutResource);
            }

            if let conv = conversation {
                DBChatHistoryStore.instance.updateItemState(for: conv, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered);
            }
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            let account = e.sessionObject.userBareJid!;
            MessageEventHandler.scheduleMessageSync(for: account);
            DBChatHistoryStore.instance.loadUnsentMessage(for: account, completionHandler: { (account, messages) in
                DispatchQueue.global(qos: .background).async {
                    for message in messages {
                        var chat = DBChatStore.instance.conversation(for: account, with: message.jid);
                        if chat == nil {
                            switch DBChatStore.instance.createChat(for: e.context, with: JID(message.jid)) {
                            case .created(let newChat):
                                chat = newChat;
                            case .found(let existingChat):
                                chat = existingChat;
                            case .none:
                                return;
                            }
                        }
                        if let dbChat = chat as? Chat {
                            if message.type == .message {
                                MessageEventHandler.sendMessage(chat: dbChat, body: message.data, url: nil, stanzaId: message.correctionStanzaId == nil ? message.stanzaId : message.correctionStanzaId, correctedMessageOriginId: message.correctionStanzaId == nil ? nil : message.stanzaId);
                            } else if message.type == .attachment {
                                MessageEventHandler.sendMessage(chat: dbChat, body: message.data, url: message.data, stanzaId: message.stanzaId);
                            }
                        }

                    }
                }
            });
        case let e as DiscoveryModule.AccountFeaturesReceivedEvent:
            if let account = e.sessionObject.userBareJid, let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID), mamModule.isAvailable {
                MessageEventHandler.syncMessagesScheduled(for: account);
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            guard Settings.enableMessageCarbons.bool() else {
                return;
            }
            guard e.features.contains(MessageCarbonsModule.MC_XMLNS) else {
                return;
            }
            guard let mcModule: MessageCarbonsModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) else {
                return;
            }
            mcModule.enable();
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to else {
                return;
            }
            
            let jid = e.action != MessageCarbonsModule.Action.received ? from : to;
            let conversation: ConversationKey = DBChatStore.instance.conversation(for: account, with: jid) ?? ConversationKeyItem(account: account, jid: jid);
                        
            DBChatHistoryStore.instance.append(for: conversation, message: e.message, source: .carbons(action: e.action));
        case let e as MessageArchiveManagementModule.ArchivedMessageReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to else {
                return;
            }
            
            let jid = from.bareJid != account ? from : to;
            
            let conversation: ConversationKey = DBChatStore.instance.conversation(for: account, with: jid) ?? ConversationKeyItem(account: account, jid: jid);
            
            DBChatHistoryStore.instance.append(for: conversation, message: e.message, source: .archive(source: e.source, version: e.version, messageId: e.messageId, timestamp: e.timestamp));
        case let e as OMEMOModule.AvailabilityChangedEvent:
            NotificationCenter.default.post(name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: e);
        default:
            break;
        }
    }
    
    static func sendAttachment(chat: Chat, originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (()->Void)?) {
        
        self.sendMessage(chat: chat, body: nil, url: uploadedUrl, chatAttachmentAppendix: appendix, messageStored: { (msgId) in
            DispatchQueue.main.async {
                if originalUrl != nil {
                    _ = DownloadStore.instance.store(originalUrl!, filename: originalUrl!.lastPathComponent, with: "\(msgId)");
                }
                completionHandler?();
            }
        })
    }

    static func sendMessage(chat: Chat, body: String?, url: String?, encrypted: ChatEncryption? = nil, stanzaId: String? = nil, chatAttachmentAppendix: ChatAttachmentAppendix? = nil, correctedMessageOriginId: String? = nil, messageStored: ((Int)->Void)? = nil) {
            guard let msg = body ?? url else {
                return;
            }

            let encryption = encrypted ?? chat.options.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!;

            let message = chat.createMessage(text: msg, id: stanzaId);
            message.messageDelivery = .request;
            message.lastMessageCorrectionId = correctedMessageOriginId;

            let account = chat.account;
            let jid = chat.jid.bareJid;

            switch encryption {
            case .omemo:
                if stanzaId == nil {
                    if let correctedMessageId = correctedMessageOriginId {
                        DBChatHistoryStore.instance.correctMessage(for: chat, stanzaId: correctedMessageId, sender: nil, data: msg, correctionStanzaId: message.id!, correctionTimestamp: Date(), newState: .outgoing_unsent);
                    } else {
                        let fingerprint = DBOMEMOStore.instance.identityFingerprint(forAccount: account, andAddress: SignalAddress(name: account.stringValue, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: account)!)));
                        DBChatHistoryStore.instance.appendItem(for: chat, state: .outgoing_unsent, sender: .me(conversation: chat), type: url == nil ? .message : .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .decrypted(fingerprint: fingerprint), appendix: chatAttachmentAppendix, linkPreviewAction: .none, completionHandler: messageStored);
                    }
                }
                XmppService.instance.tasksQueue.schedule(for: jid, task: { (completionHandler) in
                    sendEncryptedMessage(message, from: chat, completionHandler: { result in
                        switch result {
                        case .success(_):
                            DBChatHistoryStore.instance.updateItemState(for: chat, stanzaId: correctedMessageOriginId ?? message.id!, from: .outgoing_unsent, to: .outgoing, withTimestamp: correctedMessageOriginId != nil ? nil : Date());
                            
                        case .failure(let err):
                            let condition = (err is ErrorCondition) ? (err as? ErrorCondition) : nil;
                            guard condition == nil || condition! != .gone else {
                                completionHandler();
                                return;
                            }

                            var errorMessage: String? = nil;
                            if let encryptionError = err as? SignalError {
                                switch encryptionError {
                                case .noSession:
                                    errorMessage = "There is no trusted device to send message to";
                                default:
                                    errorMessage = "It was not possible to send encrypted message due to encryption error";
                                }
                            }

                            DBChatHistoryStore.instance.markOutgoingAsError(for: chat, stanzaId: message.id!, errorCondition: .undefined_condition, errorMessage: errorMessage);
                        }
                        completionHandler();
                    });
                });
            case .none:
                message.oob = url;
                let type: ItemType = url == nil ? .message : .attachment;
                if stanzaId == nil {
                    if let correctedMessageId = correctedMessageOriginId {
                        DBChatHistoryStore.instance.correctMessage(for: chat, stanzaId: correctedMessageId, sender: nil, data: msg, correctionStanzaId: message.id!, correctionTimestamp: Date(), newState: .outgoing_unsent);
                    } else {
                        DBChatHistoryStore.instance.appendItem(for: chat, state: .outgoing_unsent, sender: .me(conversation: chat), type: type, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .none, appendix: chatAttachmentAppendix, linkPreviewAction: .none, completionHandler: messageStored);
                    }
                }
                XmppService.instance.tasksQueue.schedule(for: jid, task: { (completionHandler) in
                    sendUnencryptedMessage(message, from: account, completionHandler: { result in
                        switch result {
                        case .success(_):
                            DBChatHistoryStore.instance.updateItemState(for: chat, stanzaId: correctedMessageOriginId ?? message.id!, from: .outgoing_unsent, to: .outgoing, withTimestamp: correctedMessageOriginId != nil ? nil : Date());
                        case .failure(let err):
                            guard let condition = err as? ErrorCondition, condition != .gone else {
                                completionHandler();
                                return;
                            }
                            DBChatHistoryStore.instance.markOutgoingAsError(for: chat, stanzaId: message.id!, errorCondition: err as? ErrorCondition ?? .undefined_condition, errorMessage: "Could not send message");
                        }
                        completionHandler();
                    });
                });
            }
        }

        fileprivate static func sendUnencryptedMessage(_ message: Message, from account: BareJID, completionHandler: (Result<Void,Error>)->Void) {
            guard let client = XmppService.instance.getClient(for: account), client.state == .connected else {
                completionHandler(.failure(ErrorCondition.gone));
                return;
            }

            client.context.writer.write(message);

            completionHandler(.success(Void()));
        }


        fileprivate static func sendEncryptedMessage(_ message: Message, from chat: Chat, completionHandler resultHandler: @escaping (Result<Void,Error>)->Void) {

            guard let client = chat.context as? XMPPClient, let omemoModule: OMEMOModule = client.modulesManager.getModule(OMEMOModule.ID) else {
                DBChatHistoryStore.instance.updateItemState(for: chat, stanzaId: message.id!, from: .outgoing_unsent, to: .outgoing_error(errorMessage: nil));
                resultHandler(.failure(ErrorCondition.unexpected_request));
                return;
            }

            guard client.state == .connected else {
                resultHandler(.failure(ErrorCondition.gone));
                return;
            }

            let completionHandler: ((EncryptionResult<Message, SignalError>)->Void)? = { (result) in
                switch result {
                case .failure(let error):
                    // FIXME: add support for error handling!!
                    resultHandler(.failure(error));
                case .successMessage(let encryptedMessage, _):
                    guard client.state == .connected else {
                        resultHandler(.failure(ErrorCondition.gone));
                        return;
                    }
                    client.context.writer.write(encryptedMessage);
                    resultHandler(.success(Void()));
                }
            };

            omemoModule.encode(message: message, completionHandler: completionHandler!);
        }

    static func calculateDirection(for conversation: ConversationKey, direction: MessageDirection, sender: ConversationSenderProtocol) -> MessageDirection {
        switch sender {
        case .buddy(_):
            return direction;
        case .participant(let id, _, let jid):
            if let senderJid = jid {
                return senderJid == conversation.account ? .outgoing : .incoming;
            }
            if let channel = conversation as? Channel {
                return channel.participantId == id ? .outgoing : .incoming;
            }
            // we were not able to determine if we were senders or not.
            return direction;
        case .occupant(let nickname, let jid):
            if let senderJid = jid {
                return senderJid == conversation.account ? .outgoing : .incoming;
            }
            if let room = conversation as? Room {
                return room.nickname == nickname ? .outgoing : .incoming;
            }
            // we were not able to determine if we were senders or not.
            return direction;
        default:
            return direction;
        }
    }

    static func calculateState(direction: MessageDirection, message: Message, isFromArchive archived: Bool, isMuc: Bool) -> ConversationEntryState {
        let error = message.type == StanzaType.error;
        let unread = (!archived) || isMuc;
        if direction == .incoming {
            if error {
                return unread ? .incoming_error_unread(errorMessage: message.errorText ?? message.errorCondition?.rawValue) : .incoming_error(errorMessage: message.errorText ?? message.errorCondition?.rawValue);
            }
            return unread ? .incoming_unread : .incoming;
        } else {
            if error {
                return unread ? .outgoing_error_unread(errorMessage: message.errorText ?? message.errorCondition?.rawValue) : .outgoing_error(errorMessage: message.errorText ?? message.errorCondition?.rawValue);
            }
            return .outgoing;
        }
    }
    
    private static var syncSinceQueue = DispatchQueue(label: "syncSinceQueue");
    private static var syncSince: [BareJID: Date] = [:];
    
    static func scheduleMessageSync(for account: BareJID) {
        if AccountSettings.messageSyncAuto(account).bool() {
            var syncPeriod = AccountSettings.messageSyncPeriod(account).double();
            if syncPeriod == 0 {
                syncPeriod = 72;
            }
            let syncMessagesSince = max(DBChatHistoryStore.instance.lastMessageTimestamp(for: account), Date(timeIntervalSinceNow: -1 * syncPeriod * 3600));
            // use last "received" stable stanza id for account MAM archive in case of MAM:2?
            syncSinceQueue.async {
                self.syncSince[account] = syncMessagesSince;
            }
        } else {
            syncSinceQueue.async {
                syncSince.removeValue(forKey: account);
                DBChatHistorySyncStore.instance.removeSyncPeriods(forAccount: account);
            }
        }
    }
    
    static func syncMessagesScheduled(for account: BareJID) {
        syncSinceQueue.async {
            guard AccountSettings.messageSyncAuto(account).bool(), let syncMessagesSince = syncSince[account] else {
                return;
            }
            syncMessages(for: account, since: syncMessagesSince);
        }
    }
    
    static func syncMessages(for account: BareJID, version: MessageArchiveManagementModule.Version? = nil, componentJID: JID? = nil, since: Date, rsmQuery: RSM.Query? = nil) {
        let period = DBChatHistorySyncStore.Period(account: account, component: componentJID?.bareJid, from: since, after: nil);
        DBChatHistorySyncStore.instance.addSyncPeriod(period);
        
        syncMessagePeriods(for: account, version: version, componentJID: componentJID?.bareJid)
    }
    
    static func syncMessagePeriods(for account: BareJID, version: MessageArchiveManagementModule.Version? = nil, componentJID jid: BareJID? = nil) {
        guard let first = DBChatHistorySyncStore.instance.loadSyncPeriods(forAccount: account, component: jid).first else {
            return;
        }
        syncSinceQueue.async {
            syncMessages(forPeriod: first, version: version);
        }
    }
    
    static func syncMessages(forPeriod period: DBChatHistorySyncStore.Period, version: MessageArchiveManagementModule.Version? = nil, rsmQuery: RSM.Query? = nil, retry: Int = 3) {
        guard let client = XmppService.instance.getClient(for: period.account), let mamModule: MessageArchiveManagementModule = client.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
            return;
        }
        
        let start = Date();
        let queryId = UUID().uuidString;
        mamModule.queryItems(version: version, componentJid: period.component == nil ? nil : JID(period.component!), start: period.from, end: period.to, queryId: queryId, rsm: rsmQuery ?? RSM.Query(after: period.after, max: 150), completionHandler: { (result) in
            switch result {
            case .success(let response):
                if response.complete || response.rsm == nil {
                    DBChatHistorySyncStore.instance.removeSyncPerod(period);
                    syncMessagePeriods(for: period.account, version: version, componentJID: period.component);
                } else {
                    if let last = response.rsm?.last, UUID(uuidString: last) != nil {
                        DBChatHistorySyncStore.instance.updatePeriod(period, after: last);
                    }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                        self.syncMessages(forPeriod: period, version: version, rsmQuery: response.rsm?.next(150));
                    }
                }
                os_log("for account %s fetch for component %s with id %s executed in %f s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil", queryId, Date().timeIntervalSince(start));
            case .failure(let error):
                guard client.state == .connected, retry > 0 && error != .feature_not_implemented else {
                    os_log("for account %s fetch for component %s with id %s could not synchronize message archive for: %{public}s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil", queryId, error.description);
                    return;
                }
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                    self.syncMessages(forPeriod: period, version: version, rsmQuery: rsmQuery, retry: retry - 1);
                }
            }
        });
    }

    static func extractRealAuthor(from message: Message, for conversation: ConversationKey) -> ConversationSenderProtocol? {
        if message.type == .groupchat {
            if let mix = message.mix {
                if let id = message.from?.resource, let nickname = mix.nickname {
                    return .participant(id: id, nickname: nickname, jid: mix.jid);
                }
                // invalid sender? what should we do?
                return nil;
            } else {
                // in this case it is most likely MUC groupchat message..
                if let nickname = message.from?.resource {
                    return .occupant(nickname: nickname, jid: nil);
                }
                // invalid sender? what should we do?
                return nil;
            }
        } else {
            // this can be 1-1 message from MUC..
            if conversation is Room {
                // FIXME: add new support for private MUC messages!
                if let nickname = message.from?.resource {
                    return .occupant(nickname: nickname, jid: nil);
                }
                // invalid sender? what should we do?
                return nil;
            }
        }
        return conversation.account == message.from?.bareJid ? .me(conversation: conversation) : .buddy(conversation: conversation);
    }
    
    static func itemType(fromMessage message: Message) -> ItemType {
        if let oob = message.oob {
            if (message.body == nil || oob == message.body), URL(string: oob) != nil {
                return .attachment;
            }
        }
        return .message;
    }
}
