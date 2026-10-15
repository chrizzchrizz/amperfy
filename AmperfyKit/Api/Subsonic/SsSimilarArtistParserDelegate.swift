//
//  SsSimilarArtistParserDelegate.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 15.10.26.
//  Copyright (c) 2025 Chrizz Gelbach. All rights reserved.
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

import Foundation

/// Collects the ids of the `similarArtist` elements of a `getArtistInfo2` response.
/// Entries without a real id (`-1`) are not part of the server's library and are skipped.
class SsSimilarArtistParserDelegate: SsXmlParser {
  public private(set) var artistIDs = [String]()

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

    guard elementName == "similarArtist", let id = attributeDict["id"], id != "-1" else { return }
    artistIDs.append(id)
  }
}
