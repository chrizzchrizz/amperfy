//
//  SsPlayQueueParserDelegate.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 28.10.26.
//  Copyright (c) 2026 Chrizz Gelbach. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

// MARK: - SsPlayQueueInfoParserDelegate

/// Reads only the attributes of the saved play queue, its songs are not touched.
class SsPlayQueueInfoParserDelegate: SsXmlParser {
  var playQueueInfo: ServerPlayQueueInfo?

  override func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    super.parser(
      parser,
      didStartElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName,
      attributes: attributeDict
    )
    if elementName == "playQueue" {
      playQueueInfo = ServerPlayQueueInfo(attributes: attributeDict)
    }
  }
}

// MARK: - SsPlayQueueParserDelegate

/// Creates or updates the songs of the saved play queue, `parsedSongs` keeps the queue order.
class SsPlayQueueParserDelegate: SsSongParserDelegate {
  var playQueueInfo: ServerPlayQueueInfo?

  override func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    if elementName == "playQueue" {
      playQueueInfo = ServerPlayQueueInfo(attributes: attributeDict)
    }
    super.parser(
      parser,
      didStartElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName,
      attributes: attributeDict
    )
  }
}
