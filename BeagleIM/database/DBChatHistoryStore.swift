//
// DBChatHistoryStore.swift
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

import Foundation
import TigaseSwift
import TigaseSQLite3

extension Query {
    static let messagesLastTimestampForAccount = Query("SELECT max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.state <> \(MessageState.outgoing_unsent.rawValue)");
    static let messageInsert = Query("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid, recipient_nickname, participant_id, error, encryption, fingerprint, appendix, server_msg_id, remote_msg_id, master_id) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid, :recipient_nickname, :participant_id, :error, :encryption, :fingerprint, :appendix, :server_msg_id, :remote_msg_id, :master_id)");
    // if server has MAM:2 then use server_msg_id for checking
    // if there is no result, try to match using origin-id/stanza-id (if there is one in a form of UUID) and update server_msg_id if message is found
    // if there is was no origin-id/stanza-id then use old check with timestamp range and all of that..
    static let messageFindIdByServerMsgId = Query("SELECT id FROM chat_history WHERE account = :account AND server_msg_id = :server_msg_id");
    static let messageFindIdByOriginId = Query("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND (stanza_id = :stanza_id OR correction_stanza_id = :stanza_id) AND (:author_nickname IS NULL OR author_nickname = :author_nickname) AND (:participant_id IS NULL OR participant_id = :participant_id) ORDER BY timestamp DESC");
    static let messageUpdateServerMsgId = Query("UPDATE chat_history SET server_msg_id = :server_msg_id WHERE id = :id AND server_msg_id is null");
    @available(macOS 10.15, *)
    static let messageFindLinkPreviewsForMessage = Query("SELECT id, account, jid, data FROM chat_history WHERE master_id = :master_id AND item_type = \(ItemType.linkPreview.rawValue)");
    static let messageDelete = Query("DELETE FROM chat_history WHERE id = :id");
    static let messageFindMessageOriginId = Query("select stanza_id from chat_history where id = ?");
    static let messagesFindUnsent = Query("SELECT ch.account as account, ch.jid as jid, ch.item_type as item_type, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption FROM chat_history ch WHERE ch.account = :account AND ch.state = \(MessageState.outgoing_unsent.rawValue) ORDER BY timestamp ASC");
    static let messagesFindForChat = Query("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp FROM chat_history WHERE account = :account AND jid = :jid AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.messageRetracted.rawValue), \(ItemType.attachment.rawValue))) ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
    static let messageFindPositionInChat = Query("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)");
    static let messageSearchHistory = Query("SELECT chat_history.id as id, chat_history.account as account, chat_history.jid as jid, author_nickname, author_jid, participant_id,  chat_history.timestamp as timestamp, item_type, chat_history.data as data, state, preview, chat_history.encryption as encryption, fingerprint FROM chat_history INNER JOIN chat_history_fts_index ON chat_history.id = chat_history_fts_index.rowid LEFT JOIN chats ON chats.account = chat_history.account AND chats.jid = chat_history.jid WHERE (chats.id IS NOT NULL OR chat_history.author_nickname is NULL) AND chat_history_fts_index MATCH :query AND (:account IS NULL OR chat_history.account = :account) AND (:jid IS NULL OR chat_history.jid = :jid) AND item_type = \(ItemType.message.rawValue) ORDER BY chat_history.timestamp DESC");
    static let messagesDeleteChatHistory = Query("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");
    static let messagesFindChatAttachments = Query("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp FROM chat_history WHERE account = :account AND jid = :jid AND item_type = \(ItemType.attachment.rawValue) ORDER BY timestamp DESC");
    static let messageRetract = Query("UPDATE chat_history SET item_type = :item_type, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)")
    static let messageCorrectLast = Query("UPDATE chat_history SET data = :data, state = :state, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)");
    static let messageFind = Query("SELECT id, account, jid, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_stanza_id, correction_timestamp FROM chat_history WHERE id = :id");
    static let messagesMarkAsReadBefore = Query("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    static let messageUpdateState = Query("UPDATE chat_history SET state = :newState, timestamp = COALESCE(:newTimestamp, timestamp), error = COALESCE(:error, error) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)");
    static let messageUpdate = Query("UPDATE chat_history SET appendix = :appendix WHERE id = :id");
}

class DBChatHistoryStore {

    static let MESSAGE_NEW = Notification.Name("messageAdded");
    // TODO: it looks like it is not working as expected. We should remove this notification in the future
    static let MESSAGES_MARKED_AS_READ = Notification.Name("messagesMarkedAsRead");
    static let MESSAGE_UPDATED = Notification.Name("messageUpdated");
    static let MESSAGE_REMOVED = Notification.Name("messageRemoved");
    static var instance: DBChatHistoryStore = DBChatHistoryStore.init();

    fileprivate let dispatcher: QueueDispatcher;

    static func convertToAttachments() {
        let diskCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("download", isDirectory: true);
        guard FileManager.default.fileExists(atPath: diskCacheUrl.path) else {
            return;
        }

        let previewsToConvert: [Int] = try! Database.main.reader({ database in
            try database.select("SELECT id FROM chat_history WHERE preview IS NOT NULL", cached: false).mapAll({ $0.int(for: "id") });
        })

        let removePreview = { (id: Int) in
            try! Database.main.writer({ database in
                try database.update("UPDATE chat_history SET preview = NULL WHERE id = ?", params: [id]);
            })
        };

        for id in previewsToConvert {
            guard let (item, previews, stanzaId) = try! Database.main.reader({ database in
                return try database.select("SELECT id, account, jid, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, preview, stanza_id, correction_timestamp FROM chat_history WHERE id = ?", cached: true, params: [id]).mapFirst({ cursor -> (ChatMessage, [String:String], String?)? in
                    let account: BareJID = cursor["account"]!;
                    let jid: BareJID = cursor["jid"]!;
                    let stanzaId: String? = cursor["stanza_id"];
                    guard let item = DBChatHistoryStore.instance.itemFrom(cursor: cursor, for: account, with: jid) as? ChatMessage, let previewStr: String = cursor["preview"] else {
                        return nil;
                    }
                    var previews: [String:String] = [:];
                    previewStr.split(separator: "\n").forEach { (line) in
                        let tmp = line.split(separator: "\t").map({String($0)});
                        if (!tmp[1].starts(with: "ERROR")) && (tmp[1] != "NONE") {
                            previews[tmp[0]] = tmp[1];
                        }
                    }
                    return (item, previews, stanzaId);
                });
            }) else {
                return;
            }

            if previews.isEmpty {
                removePreview(item.id);
            } else {
                print("converting for:", item.account, "with:", item.jid, "previews:", previews);
                if previews.count == 1 {
                    let isAttachmentOnly = URL(string: item.message) != nil;

                    if isAttachmentOnly {
                        let appendix = ChatAttachmentAppendix();
                        DBChatHistoryStore.instance.appendItem(for: item.account, with: JID(item.jid), state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .attachment, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, appendix: appendix, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                DBChatHistoryStore.instance.remove(item: item);
                        });
                    } else {
                        if #available(macOS 10.15, *) {
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: JID(item.jid), state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: previews.keys.first ?? item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                removePreview(item.id);
                            });
                        } else {
                            removePreview(item.id);
                        }
                    }
                } else {
                    if #available(macOS 10.15, *) {
                        let group = DispatchGroup();
                        group.enter();

                        group.notify(queue: DispatchQueue.main, execute: {
                            removePreview(item.id);
                        })

                        for (url, _) in previews {
                            group.enter();
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: JID(item.jid), state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                    group.leave();
                            });
                        }
                        group.leave();
                    } else {
                        removePreview(item.id);
                    }
                }
            }
        }

        try? FileManager.default.removeItem(at: diskCacheUrl);
    }


    public init() {
        dispatcher = QueueDispatcher(label: "chat_history_store");
    }

    open func process(chatState: ChatState, for account: BareJID, with jid: JID) {
        dispatcher.async {
            DBChatStore.instance.process(chatState: chatState, for: account, with: jid.bareJid);
        }
    }

    enum MessageSource {
        case stream
        case archive(source: BareJID, version: MessageArchiveManagementModule.Version, messageId: String, timestamp: Date)
        case carbons(action: MessageCarbonsModule.Action)
    }
    private var enqueuedItems = 0;


    open func append(for account: BareJID, message: Message, source: MessageSource) {
        let direction: MessageDirection = account == message.from?.bareJid ? .outgoing : .incoming;
        guard let jidFull = direction == .outgoing ? message.to : message.from else {
            // sender jid should always be there..
            return;
        }

        let jid = jidFull.withoutResource;

        let (decryptedBody, encryption, fingerprint) = MessageEventHandler.prepareBody(message: message, forAccount: account);
        let mixInvitation = message.mixInvitation;

        var itemType = MessageEventHandler.itemType(fromMessage: message);
        let stanzaId = message.originId ?? message.id;
        var stableIds = message.stanzaId;
        var fromArchive = false;

        var inTimestamp: Date?;

        switch source {
        case .archive(let source, let version, let messageId, let timestamp):
            if version == .MAM2 {
                if stableIds == nil {
                    stableIds = [source: messageId];
                } else {
                    stableIds?[source] = messageId;
                }
            }
            inTimestamp = timestamp;
            if message.type == .groupchat {
                fromArchive = false; //source != account;
            } else {
                fromArchive = true;
            }
        default:
            inTimestamp = message.delay?.stamp;
            break;
        }

        let serverMsgId: String? = stableIds?[account];
        let remoteMsgId: String? = stableIds?[jid.bareJid];

        let (authorNickname, authorJid, recipientNickname, participantId) = MessageEventHandler.extractRealAuthor(from: message, for: account, with: jidFull);

        let state = MessageEventHandler.calculateState(direction: MessageEventHandler.calculateDirection(direction: direction, for: account, with: jid.bareJid, authorNickname: authorNickname, authorJid: authorJid), isError: (message.type ?? .chat) == .error, isFromArchive: fromArchive, isMuc: message.type == .groupchat && message.mix == nil);

        var appendix: AppendixProtocol? = nil;
        if itemType == .message, let mixInivation = mixInvitation {
            itemType = .invitation;
            appendix = ChatInvitationAppendix(mixInvitation: mixInivation);
        }

        let timestamp = Date(timeIntervalSince1970: Double(Int64((inTimestamp ?? Date()).timeIntervalSince1970 * 1000)) / 1000);

        guard let body = decryptedBody ?? (mixInvitation != nil ? "Invitation" : nil) else {
            if let retractedId = message.messageRetractionId, let originId = stanzaId {
                dispatcher.async {
                    self.retractMessageSync(for: account, with: jid, stanzaId: retractedId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
                }
                return;
            }
            // only if carbon!!
            switch source {
            case .carbons(let action):
                if action == .received {
                    if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                        DBChatHistoryStore.instance.process(chatState: chatState, for: account, with: jid);
                    }
                }
            default:
                if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                    DBChatHistoryStore.instance.process(chatState: chatState, for: account, with: jid);
                }
                break;
            }
            return;
        }

        dispatcher.async {
            guard !state.isError || stanzaId == nil || !self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId!, errorCondition: message.errorCondition, errorMessage: message.errorText) else {
                return;
            }

            if let retractedId = message.messageRetractionId, let originId = stanzaId {
                self.retractMessageSync(for: account, with: jid, stanzaId: retractedId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
                return;
            }
            if let originId = stanzaId, let correctedMessageId = message.lastMessageCorrectionId, self.correctMessageSync(for: account, with: jid, stanzaId: correctedMessageId, authorNickname: authorNickname, participantId: participantId, data: body, correctionStanzaId: originId, correctionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, newState: state) {
                if let chatState = message.chatState {
                    DBChatStore.instance.process(chatState: chatState, for: account, with: jid.bareJid);
                }
                return;
            }

            if let stableId = serverMsgId, let existingMessageId = self.findItemId(for: account, serverMsgId: stableId) {
                return;
            }

            if let originId = stanzaId, let existingMessageId = self.findItemId(for: account, with: jid, originId: originId, authorNickname: authorNickname, participantId: participantId) {
                if let stableId = serverMsgId {
                    try! Database.main.writer({ database in
                        try database.update(query: .messageUpdateServerMsgId, params: ["id": existingMessageId, "server_msg_id": stableId]);
                    })
                }
                return;
            }

            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: itemType, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: body, chatState: message.chatState, errorCondition: message.errorCondition, errorMessage: message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, appendix: appendix, linkPreviewAction: .auto, masterId: nil, completionHandler: nil);
        }
    }

    enum LinkPreviewAction {
        case auto
        case none
        case only
    }

    private func findItemId(for account: BareJID, serverMsgId: String) -> Int? {
        return try! Database.main.reader({ database -> Int? in
            return try database.select(query: .messageFindIdByServerMsgId, params: ["server_msg_id": serverMsgId, "account": account]).mapFirst({ $0.int(for: "id") });
        })
    }

    private func findItemId(for account: BareJID, with jid: JID, originId: String, authorNickname: String?, participantId: String?) -> Int? {
        return try! Database.main.reader({ database -> Int? in
            return try database.select(query: .messageFindIdByOriginId, params: ["stanza_id": originId, "account": account, "jid": jid, "author_nickname": authorNickname, "participant_id": participantId]).mapFirst({ $0.int(for: "id") });
        })
    }

//    private func findItemId(for account: BareJID, with jid: BareJID, timestamp: Date, direction: MessageDirection, itemType: ItemType, stanzaId: String?, authorNickname: String?, data: String?) -> Int? {
//        let range = stanzaId == nil ? 5.0 : 60.0;
//        let ts_from = timestamp.addingTimeInterval(-60 * range);
//        let ts_to = timestamp.addingTimeInterval(60 * range);
//
//        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
//
//        return try! self.findItemFallback.findFirst(params, map: { cursor -> Int? in
//            return cursor["id"];
//        })
//    }

    private func appendItemSync(for account: BareJID, with jid: JID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState?, errorCondition: ErrorCondition?, errorMessage: String? , encryption: MessageEncryption, encryptionFingerprint: String?, appendix: AppendixProtocol?, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {
        var item: ChatViewItemProtocol?;
        if linkPreviewAction != .only {
            let params: [String:Any?] = ["account": account, "jid": jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": stanzaId, "author_nickname": authorNickname, "author_jid": authorJid, "recipient_nickname": recipientNickname, "participant_id": participantId, "encryption": encryption.rawValue, "fingerprint": encryptionFingerprint, "error": state.isError ? (errorMessage ?? errorCondition?.rawValue ?? "Unknown error") : nil, "appendix": appendix, "server_msg_id": serverMsgId, "remote_msg_id": remoteMsgId, "master_id": masterId];

            guard let msgId = try! Database.main.writer({ database -> Int? in
                try database.insert(query: .messageInsert, params: params);
                return database.lastInsertedRowId;
            }) else {
                return;
            }
            completionHandler?(msgId);

            switch type {
            case .message:
                item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid.bareJid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage, correctionTimestamp: nil);
            case .invitation:
                item = ChatInvitation(id: msgId, timestamp: timestamp, account: account, jid: jid.bareJid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix as! ChatInvitationAppendix, error: errorMessage);
            case .attachment:
                item = ChatAttachment(id: msgId, timestamp: timestamp, account: account, jid: jid.bareJid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: (appendix as? ChatAttachmentAppendix) ?? ChatAttachmentAppendix(), error: errorMessage);
            case .linkPreview:
                if #available(macOS 10.15, *), Settings.linkPreviews.bool() {
                    item = ChatLinkPreview(id: msgId, timestamp: timestamp, account: account, jid: jid.bareJid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
                }
            case .messageRetracted, .attachmentRetracted:
                // nothing to do, as we do not want notifications for that (at least for now and no item of that type would be created in here!
                break;
            }
            if item != nil {
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, itemType: type, message: encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil, senderNickname: authorNickname) {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
                }
            }
        }
        if linkPreviewAction != .none && type == .message, let id = item?.id {
            self.generatePreviews(forItem: id, account: account, jid: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, timestamp: timestamp, data: data);
        }
    }

    open func appendItem(for account: BareJID, with jid: JID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp inTimestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState? = nil, errorCondition: ErrorCondition? = nil, errorMessage: String? = nil, encryption: MessageEncryption, encryptionFingerprint: String?, appendix: AppendixProtocol? = nil, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {

        let timestamp = Date(timeIntervalSince1970: Double(Int64(inTimestamp.timeIntervalSince1970 * 1000)) / 1000);
        dispatcher.async {
            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: type, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: data, chatState: chatState, errorCondition: errorCondition, errorMessage: errorMessage, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, linkPreviewAction: linkPreviewAction, masterId: masterId, completionHandler: completionHandler);
        }
    }

    open func removeHistory(for account: BareJID, with jid: JID?) {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.delete(query: .messagesDeleteChatHistory, cached: false, params: ["account": account, "jid": jid]);
            })
        }
    }

    open func correctMessage(for account: BareJID, with jid: JID, stanzaId: String, authorNickname: String?, participantId: String?, data: String, correctionStanzaId: String?, correctionTimestamp: Date, newState: MessageState) {
        let timestamp = Date(timeIntervalSince1970: Double(Int64((correctionTimestamp).timeIntervalSince1970 * 1000)) / 1000);
        dispatcher.async {
            _ = self.correctMessageSync(for: account, with: jid, stanzaId: stanzaId,  authorNickname: authorNickname, participantId: participantId, data: data, correctionStanzaId: correctionStanzaId, correctionTimestamp: timestamp, serverMsgId: nil, remoteMsgId: nil, newState: newState);
        }
    }

    // TODO: Is it not "the same" as message retraction? Maybe we should unify?
    private func correctMessageSync(for account: BareJID, with jid: JID, stanzaId: String, authorNickname: String?, participantId: String?, data: String, correctionStanzaId: String?, correctionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?, newState: MessageState) -> Bool {
        // we need to check participant-id/sender nickname to make it work correctly
        // moreover, stanza-id should be checked with origin-id for MUC/MIX (not message id)
        // MIX/MUC should send origin-id if they assume to use last message correction!
        if let oldItem = self.findItem(for: account, with: jid, originId: stanzaId, authorNickname: authorNickname, participantId: participantId) {
            let itemId = oldItem.id;
            let params: [String: Any?] = ["id": itemId, "data": data, "state": newState.rawValue, "correction_stanza_id": correctionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": correctionTimestamp];
            let updated = try! Database.main.writer({ database -> Int in
                try! database.update(query: .messageCorrectLast, params: params);
                return database.changes;
            })
            if updated > 0 {
                let newMessageState: MessageState = (oldItem.state.direction == .incoming) ? (oldItem.state.isUnread ? .incoming : (newState.isUnread ? .incoming_unread : .incoming)) : (.outgoing);
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: oldItem.timestamp, itemType: .message, message: data, state: newMessageState, completionHandler: {
                    print("chat store state updated with message state:", newMessageState.rawValue, "old state:", oldItem.state.rawValue, "new state:", newState.rawValue);
                })

                print("correcing previews for master id:", itemId);
                self.itemUpdated(withId: itemId, for: account, with: jid);
                self.previewGenerationDispatcher.async(flags: .barrier, execute: {
                    self.dispatcher.sync {
                        print("removing previews for master id:", itemId);
                        self.removePreviews(idOfRelatedToItem: itemId);

                        if newState != .outgoing_unsent {
                            self.generatePreviews(forItem: itemId, account: account, jid: jid, state: newState);
                        }
                    }
                })
            }
            return true;
        } else {
            return false;
        }
    }

    public func retractMessage(for account: BareJID, with jid: JID, stanzaId: String, authorNickname: String?, participantId: String?, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) {
        dispatcher.async {
            _ = self.retractMessageSync(for: account, with: jid, stanzaId: stanzaId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: retractionStanzaId, retractionTimestamp: retractionTimestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
        }
    }

    private func retractMessageSync(for account: BareJID, with jid: JID, stanzaId: String, authorNickname: String?, participantId: String?, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) -> Bool {
        if let oldItem = self.findItem(for: account, with: jid, originId: stanzaId, authorNickname: authorNickname, participantId: participantId) {
            let itemId = oldItem.id;
            var itemType: ItemType = .messageRetracted;
            if oldItem is ChatAttachment {
                itemType = .attachmentRetracted;
            }
            let params: [String: Any?] = ["id": itemId, "item_type": itemType.rawValue, "correction_stanza_id": retractionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": retractionTimestamp];
            let updated = try! Database.main.writer({ database -> Int in
                try database.update(query: .messageRetract, params: params);
                return database.changes;
            })
            if updated > 0 {
                // what should be sent to "newMessage" how to reatract message from there??
                let activity: LastChatActivity = DBChatStore.instance.getLastActivity(for: account, jid: jid) ?? .message("", direction: .incoming, sender: nil);
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: oldItem.timestamp, lastActivity: activity, state: oldItem.state.direction == .incoming ? .incoming : .outgoing, completionHandler: {
                    print("chat store state updated with message retraction");
                })
                if oldItem.state.isUnread {
                    DBChatStore.instance.markAsRead(for: account, with: jid, count: 1);
                }

                self.itemUpdated(withId: itemId, for: account, with: jid);
//                   self.itemRemoved(withId: itemId, for: account, with: jid);
                self.previewGenerationDispatcher.async(flags: .barrier, execute: {
                    self.dispatcher.sync {
                        print("removing previews for master id:", itemId);
                        self.removePreviews(idOfRelatedToItem: itemId);
                    }
                })
            }
            return true;
        } else {
            return false;
        }
    }

    private func findItem(for account: BareJID, with jid: JID, originId: String, authorNickname: String?, participantId: String?) -> ChatViewItemProtocol? {
        guard let itemId = findItemId(for: account, with: jid, originId: originId, authorNickname: authorNickname, participantId: participantId) else {
            return nil;
        }
        return message(withId: itemId);
    }

    private func message(withId msgId: Int) -> ChatViewItemProtocol? {
        return try! Database.main.writer({ database -> ChatViewItemProtocol? in
            return try database.select(query: .messageFind, params: ["id": msgId]).mapFirst({ cursor -> ChatViewItemProtocol? in
                return self.itemFrom(cursor: cursor);
            });
        });
    }

    private func generatePreviews(forItem masterId: Int, account: BareJID, jid: JID, state: MessageState) {
        if #available(macOS 10.15, *) {
            guard let item = self.message(withId: masterId) as? ChatMessage else {
                return;
            }

            self.generatePreviews(forItem: item.id, account: item.account, jid: JID(item.jid), state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: item.recipientNickname, participantId: item.participantId, timestamp: item.timestamp, data: item.message);
        }
    }

    private var previewsInProgress: [Int: UUID] = [:];
    private let previewGenerationDispatcher = QueueDispatcher(label: "chat_history_store", attributes: [.concurrent]);

    private func generatePreviews(forItem masterId: Int, account: BareJID, jid: JID, state messageState: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, timestamp: Date, data: String) {
        if #available(macOS 10.15, *) {
            let state = messageState == .incoming_unread ? .incoming : messageState;
            let uuid = UUID();
            previewsInProgress[masterId] = uuid;
        previewGenerationDispatcher.async {
            print("generating previews for master id:", masterId, "uuid:", uuid);
        // if we may have previews, we should add them here..
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
            let matches = detector.matches(in: data, range: NSMakeRange(0, data.utf16.count));

            guard self.dispatcher.sync(execute: {
                let valid =  self.previewsInProgress[masterId] == uuid;
                if valid {
                    self.previewsInProgress.removeValue(forKey: masterId);
                }
                return valid;
            }) else {
                return;
            }
            print("adding previews for master id:", masterId, "uuid:", uuid);
            matches.forEach { match in
                if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                    if (data as NSString).range(of: "http", options: .caseInsensitive, range: match.range).location == match.range.location {
                        DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: url.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                    }
                }
                if let address = match.components {
                    let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                    let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                    DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: mapUrl.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                }
            }
        }
        }
        }
    }

    fileprivate func processOutgoingError(for account: BareJID, with jid: JID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) -> Bool {
        guard let itemId = getItemId(for: account, with: jid, stanzaId: stanzaId) else {
            return false;
        }

        guard try! Database.main.writer({ database -> Int in
            try! database.update(query: .messageUpdateState, params: ["id": itemId, "state": MessageState.outgoing_error_unread.rawValue, "error": errorMessage ?? errorCondition?.rawValue ?? "Unknown error"]);
            return database.changes;
        }) > 0 else {
            return false;
        }
        DBChatStore.instance.newMessage(for: account, with: jid, timestamp: Date(timeIntervalSince1970: 0), itemType: nil, message: nil, state: .outgoing_error_unread) {
            self.itemUpdated(withId: itemId, for: account, with: jid);
        }
        return true;
    }

    open func markOutgoingAsError(for account: BareJID, with jid: JID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) {
        dispatcher.async {
            _ = self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId, errorCondition: errorCondition, errorMessage: errorMessage);
        }
    }

    open func markAsRead(for account: BareJID, with jid: JID, before: Date) {
        dispatcher.async {
            let updatedRecords = try! Database.main.writer({ database -> Int in
                try database.update(query: .messagesMarkAsReadBefore, params: ["account": account, "jid": jid, "before": before]);
                return database.changes;
            })
            if updatedRecords > 0 {
                DBChatStore.instance.markAsRead(for: account, with: jid, count: updatedRecords);
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: self, userInfo: ["account": account, "jid": jid]);
                }
            }
        }
    }

    open func getItemId(for account: BareJID, with jid: JID, stanzaId: String) -> Int? {
        return dispatcher.sync {
            return self.findItemId(for: account, with: jid, originId: stanzaId, authorNickname: nil, participantId: nil);
        }
    }

    open func itemPosition(for account: BareJID, with jid: BareJID, msgId: Int) -> Int? {
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                return try database.select(query: .messageFindPositionInChat, params: ["account": account, "jid": jid, "msgId": msgId, "showLinkPreviews": linkPreviews]).mapFirst({ $0.int(at: 0) });
            })
        }
    }

    open func updateItemState(for account: BareJID, with jid: JID, stanzaId: String, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date? = nil) {
        dispatcher.async {
            guard let msgId = self.getItemId(for: account, with: jid, stanzaId: stanzaId) else {
                return;
            }

            self.updateItemState(for: account, with: jid, itemId: msgId, from: oldState, to: newState, withTimestamp: timestamp);
        }
    }

    open func updateItemState(for account: BareJID, with jid: JID, itemId msgId: Int, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date?) {
        dispatcher.async {
            guard try! Database.main.writer({ database -> Int in
                try database.update(query: .messageUpdateState, params:  ["id": msgId, "oldState": oldState.rawValue, "newState": newState.rawValue, "newTimestamp": timestamp]);
                return database.changes;
            }) > 0 else {
                return;
            }
            self.itemUpdated(withId: msgId, for: account, with: jid);
            if oldState == .outgoing_unsent && newState != .outgoing_unsent {
                self.generatePreviews(forItem: msgId, account: account, jid: jid, state: newState);
            }
        }
    }

    open func remove(item: ChatViewItemProtocol) {
        dispatcher.async {
            guard try! Database.main.writer({ database in
                try database.delete(query: .messageDelete, cached: false, params: ["id": item.id]);
                return database.changes;
            }) > 0 else {
                return;
            }
            self.itemRemoved(withId: item.id, for: item.account, with: item.jid);
            self.removePreviews(idOfRelatedToItem: item.id);
        }
    }

    private func removePreviews(idOfRelatedToItem masterId: Int) {
        if #available(macOS 10.15, *) {
            let linkPreviews = try! Database.main.reader({ database in
                return try database.select(query: .messageFindLinkPreviewsForMessage, cached: false, params: ["master_id": masterId]).mapAll({ cursor -> (Int, BareJID, BareJID)? in
                    guard let id: Int = cursor["id"], let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                        return nil;
                    }
                    return (id, account, jid);
                })
            })

            // for chat message we might have a link previews which we need to remove..
            guard !linkPreviews.isEmpty else {
                return;
            }
            for (id, account, jid) in linkPreviews {
                // this is a preview and needs to be removed..
                let removeLinkParams: [String: Any?] = ["id": id];
                if try! Database.main.writer({ database -> Int in
                    try database.delete(query: .messageDelete, cached: false, params: removeLinkParams);
                    return database.changes;
                }) > 0 {
                    self.itemRemoved(withId: id, for: account, with: jid);
                }
            }
        }
    }

    func originId(for account: BareJID, with jid: BareJID, id: Int, completionHandler: @escaping (String)->Void ){
        dispatcher.async {
            if let stanzaId = try! Database.main.reader({ dataase in
                try dataase.select(query: .messageFindMessageOriginId, cached: false, params: ["id": id]).mapFirst({ $0.string(for: "stanza_id")});
            }) {
                DispatchQueue.main.async {
                    completionHandler(stanzaId);
                }
            }
        }
    }

    open func updateItem(for account: BareJID, with jid: BareJID, id: Int, updateAppendix updateFn: @escaping (inout ChatAttachmentAppendix)->Void) {
        dispatcher.async {
            guard let item = self.message(withId: id) as? ChatAttachment else {
                return;
            }
            updateFn(&item.appendix);
            try! Database.main.writer({ database in
                try database.update(query: .messageUpdate, params: ["id": id, "appendix": item.appendix]);
            })
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            }
        }
    }

    func loadUnsentMessage(for account: BareJID, completionHandler: @escaping (BareJID,[UnsentMessage])->Void) {
        dispatcher.async {
            let messages = try! Database.main.reader({ database in
                try database.select(query: .messagesFindUnsent, cached: false, params: ["account": account]).mapAll(UnsentMessage.from(cursor: ))
            })
            completionHandler(account, messages);
        }
    }

    fileprivate func itemUpdated(withId id: Int, for account: BareJID, with jid: JID) {
        dispatcher.async {
            guard let item = self.message(withId: id) else {
                return;
            }
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
        }
    }

    fileprivate func itemRemoved(withId id: Int, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_REMOVED, object: DeletedMessage(id: id, account: account, jid: jid));
        }
    }

    func lastMessageTimestamp(for account: BareJID) -> Date {
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                return try database.select(query: .messagesLastTimestampForAccount, cached: false, params: ["account": account]).mapFirst({ $0.date(for: "timestamp") }) ?? Date(timeIntervalSince1970: 0);
            });
        }
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int, completionHandler: @escaping (([ChatViewItemProtocol]) -> Void)) {
        dispatcher.async {
            if before != nil {
                let offset = try! Database.main.reader({ database in
                    return try database.select(query: .messageFindPositionInChat, params: ["account": account, "jid": jid, "msgId": before!, "showLinkPreviews": self.linkPreviews]).mapFirst({ $0.int(at: 0) });
                }) ?? 0;
                completionHandler(self.history(for: account, jid: jid, offset: offset, limit: limit));
            } else {
                completionHandler(self.history(for: account, jid: jid, offset: 0, limit: limit));
            }
        }
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int) -> [ChatViewItemProtocol] {
        return dispatcher.sync {
            if before != nil {
                let offset = try! Database.main.reader({ database in
                    return try database.select(query: .messageFindPositionInChat, params: ["account": account, "jid": jid, "msgId": before!, "showLinkPreviews": self.linkPreviews]).mapFirst({ $0.int(at: 0) });
                }) ?? 0;
                return history(for: account, jid: jid, offset: offset, limit: limit);
            } else {
                return history(for: account, jid: jid, offset: 0, limit: limit);
            }
        }
    }

    open func searchHistory(for account: BareJID? = nil, with jid: BareJID? = nil, search: String, completionHandler: @escaping ([ChatViewItemProtocol])->Void) {
        // TODO: Remove this dispatch. async is OK but it is not needed to be done in a blocking maner
        dispatcher.async {
            let tokens = search.unicodeScalars.split(whereSeparator: { (c) -> Bool in
                return CharacterSet.punctuationCharacters.contains(c) || CharacterSet.whitespacesAndNewlines.contains(c);
            }).map({ (s) -> String in
                return String(s) + "*";
            });
            let query = tokens.joined(separator: " + ");
            print("searching for:", tokens, "query:", query);
            let items = try! Database.main.reader({ database in
                try database.select(query: .messageSearchHistory, params: ["account": account, "jid": jid, "query": query]).mapAll({ cursor -> ChatViewItemProtocol? in
                    guard let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                        return nil;
                    }
                    return self.itemFrom(cursor: cursor, for: account, with: jid);
                })
            });
            completionHandler(items);
        }
    }

    private func history(for account: BareJID, jid: BareJID, offset: Int, limit: Int) -> [ChatViewItemProtocol] {
        return try! Database.main.reader({ database in
            return try database.select(query: .messagesFindForChat, params: ["account": account, "jid": jid, "offset": offset, "limit": limit, "showLinkPreviews": linkPreviews]).mapAll({ cursor -> ChatViewItemProtocol? in self.itemFrom(cursor: cursor, for: account, with: jid) });
        })
    }

    public func loadAttachments(for account: BareJID, with jid: BareJID, completionHandler: @escaping ([ChatAttachment])->Void) {
        // TODO: Why it is done in async manner but on a single thread? what is the point here?
        let params: [String: Any?] = ["account": account, "jid": jid];
        dispatcher.async {
            let attachments = try! Database.main.reader({ database in
                return try database.select(query: .messagesFindChatAttachments, cached: false, params: params).mapAll({ cursor -> ChatAttachment? in
                    return self.itemFrom(cursor: cursor, for: account, with: jid) as? ChatAttachment;
                })
            })
            completionHandler(attachments);
        }
    }

    fileprivate var linkPreviews: Bool {
        if #available(macOS 10.15, *) {
            return Settings.linkPreviews.bool();
        } else {
            return false;
        }
    }

    private func itemFrom(cursor: Cursor) -> ChatViewItemProtocol? {
        guard let account = cursor.bareJid(for: "account"), let jid = cursor.bareJid(for: "jid") else {
            return nil;
        }
        return itemFrom(cursor: cursor, for: account, with: jid);
    }

    fileprivate func itemFrom(cursor: Cursor, for account: BareJID, with jid: BareJID) -> ChatViewItemProtocol? {
        let id: Int = cursor["id"]!;
        let stateInt: Int = cursor["state"]!;
        let timestamp: Date = cursor["timestamp"]!;

        guard let entryType = ItemType(rawValue: cursor["item_type"]!) else {
            return nil;
        }

        var correctionTimestamp: Date? = cursor["correction_timestamp"];
        if correctionTimestamp?.timeIntervalSince1970 == 0 {
            correctionTimestamp = nil;
        }

        let authorNickname: String? = cursor["author_nickname"];
        let authorJid: BareJID? = cursor["author_jid"];
        let recipientNickname: String? = cursor["recipient_nickname"];
        let participantId: String? = cursor["participant_id"];

        let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
        let encryptionFingerprint: String? = cursor["fingerprint"];
        let error: String? = cursor["error"];

        //let appendix: String? = cursor["appendix"];
        // maybe we should have a "supplement" object which would provide additional info? such as additional data, etc..
        switch entryType {
        case .message:
            let message: String = cursor["data"]!;

            var preview: [String: String]? = nil;
            if let previewStr: String = cursor["preview"] {
                preview = [:];
                previewStr.split(separator: "\n").forEach { (line) in
                    let tmp = line.split(separator: "\t");
                    preview?[String(tmp[0])] = String(tmp[1]);
                }
            }

            return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error, correctionTimestamp: correctionTimestamp);
        case .messageRetracted:
            return ChatMessageRetracted(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
        case .invitation:
            let message: String? = cursor["data"];
            guard let appendix: ChatInvitationAppendix = cursor.object(for: "appendix")else {
                return nil;
            }
            return ChatInvitation(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, error: error)
        case .attachment:
            let url: String = cursor["data"]!;

            let appendix = cursor.object(for: "appendix") ?? ChatAttachmentAppendix();

            return ChatAttachment(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, error: error);
        case .linkPreview:
            let url: String = cursor["data"]!;
            return ChatLinkPreview(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error)
        case .attachmentRetracted:
            // nothing in here, as were are removing retracted messages from the UI
            return nil;
        }

    }

}

public enum ItemType: Int {
    case message = 0
    case attachment = 1
    // how about new type called link preview? this way we would have a far less data kept in a single item..
    // we could even have them separated to the new item/entry during adding message to the store..
    @available(macOS 10.15, *)
    case linkPreview = 2
    // with that in place we can have separate metadata kept "per" message as it is only one, so message id can be id of associated metadata..
    case invitation = 3
    case messageRetracted = 4
    case attachmentRetracted = 5;
}

class UnsentMessage {
    let jid: BareJID;
    let type: ItemType;
    let data: String;
    let stanzaId: String;
    let encryption: MessageEncryption;
    let correctionStanzaId: String?;

    init(jid: BareJID, type: ItemType, data: String, stanzaId: String, encryption: MessageEncryption, correctionStanzaId: String?) {
        self.jid = jid;
        self.type = type;
        self.data = data;
        self.stanzaId = stanzaId;
        self.encryption = encryption;
        self.correctionStanzaId = correctionStanzaId;
    }

    static func from(cursor: Cursor) -> UnsentMessage? {
        guard let jid = cursor.bareJid(for: "jid"), let type = ItemType(rawValue: cursor.int(for: "item_type")!), let data = cursor.string(for: "data"), let stanzaId = cursor.string(for: "stanza_id"), let encryption = MessageEncryption(rawValue: cursor.int(for: "encryption") ?? 0) else {
            return nil;
        }
        return UnsentMessage(jid: jid, type: type, data: data, stanzaId: stanzaId, encryption: encryption, correctionStanzaId: cursor.string(for: "correction_stanza_id"));
    }
}
