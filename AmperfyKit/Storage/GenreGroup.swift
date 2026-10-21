//
//  GenreGroup.swift
//  AmperfyKit
//
//  Copyright (c) 2026 Maximilian Bauer. All rights reserved.
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

// MARK: - GenreGroup

/// A named group of genres, used e.g. by the genre section of the home screen.
/// Genre names like "Hip-Hop", "Hip Hop" and "Rap" are merged into one group.
public struct GenreGroup: Sendable, Hashable {
  public let name: String
  /// Names that belong to this group. A genre matches if its normalized name is equal to an
  /// alias or starts/ends with an alias as whole words ("Alternative Rock" matches "alternative").
  public let aliases: [String]

  public init(name: String, aliases: [String]) {
    self.name = name
    self.aliases = aliases
  }

  fileprivate var normalizedAliases: [String] {
    ([name] + aliases).map { GenreGroups.normalize($0) }
  }
}

// MARK: - GenreGroups

public enum GenreGroups {
  /// Only genres of these groups are considered. Adjust here to change the selection or merging.
  /// The ORDER matters: a genre belongs to the first matching group, so more specific groups
  /// have to come first (e.g. "Folk Rock" -> Folk, "Indie Pop" -> Indie, "Dance Pop" -> Dance).
  public static let all: [GenreGroup] = [
    GenreGroup(name: "Alternative", aliases: ["alt", "alternativ"]),
    GenreGroup(name: "Indie", aliases: []),
    GenreGroup(name: "Hip Hop", aliases: ["hiphop", "rap"]),
    GenreGroup(name: "Electronic", aliases: ["electronica", "electro", "edm"]),
    GenreGroup(name: "Dance", aliases: []),
    GenreGroup(name: "Funk", aliases: []),
    GenreGroup(name: "Country", aliases: []),
    GenreGroup(name: "Folk", aliases: []),
    GenreGroup(name: "Pop", aliases: []),
    GenreGroup(name: "Rock", aliases: []),
  ]

  /// The first group the genre name belongs to, nil if the genre is not part of any group.
  public static func group(forGenreName genreName: String) -> GenreGroup? {
    let normalizedName = normalize(genreName)
    guard !normalizedName.isEmpty else { return nil }
    return all.first { group in
      group.normalizedAliases.contains { alias in
        normalizedName == alias ||
          normalizedName.hasPrefix(alias + " ") ||
          normalizedName.hasSuffix(" " + alias)
      }
    }
  }

  /// Lowercased, every run of non-alphanumeric characters becomes a single space.
  static func normalize(_ name: String) -> String {
    name.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
