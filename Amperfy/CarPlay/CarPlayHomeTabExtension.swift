//
//  CarPlayHomeTabExtension.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 02.01.26.
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

import AmperfyKit
import CarPlay
import CoreData
import Foundation

extension CarPlaySceneDelegate {
  func updateHomeSections() {
    guard let sharedHome else { return }
    let alreadyCreatedData = homeRowData
    let requestedData = sharedHome.data
    guard alreadyCreatedData !=
      requestedData else {
      return
    }
    let homeRows = createHomeImageRows()
    let homeSection = CPListSection(items: homeRows, header: nil, sectionIndexTitle: nil)
    homeTab.updateSections([homeSection])
  }

  func createHomeImageRows() -> [CPListImageRowItem] {
    guard let sharedHome else { return [] }
    var imageRows = [CPListImageRowItem]()
    // decade and genre sections are hidden as long as they have no albums (like in the app home)
    for section in sharedHome.orderedVisibleSections
      where !section.isFixedDecadeOrGenre || !(sharedHome.data[section] ?? []).isEmpty {
      if let row = homeImageRows[section] {
        let alreadyCreatedData = homeRowData[section]
        let requestedData = sharedHome.data[section]
        if alreadyCreatedData !=
          requestedData {
          let imageRowElements = createHomeRowImageElements(section: section, isDetail: false)
          row.elements = imageRowElements
        }
        imageRows.append(row)
      } else if let row = createHomeRow(section: section, isDetailTemplate: false) {
        homeImageRows[section] = row
        imageRows.append(row)
      }
    }
    return imageRows
  }

  func createHomeRow(section: HomeSection, isDetailTemplate: Bool) -> CPListImageRowItem? {
    guard let sharedHome else { return nil }
    let alreadyCreatedData = homeRowData[section]
    let requestedData = sharedHome.data[section]
    if !isDetailTemplate,
       alreadyCreatedData ==
       requestedData {
      return homeImageRows[section]
    }

    let imageRowElements = createHomeRowImageElements(section: section, isDetail: isDetailTemplate)
    let isRandomSection = section.isRandomSection

    var title: String?
    if !isDetailTemplate {
      title = section.headerTitle
    } else if isRandomSection {
      title = "Refresh"
    }

    let row = CPListImageRowItem(
      text: title,
      elements: imageRowElements,
      allowsMultipleLines: isDetailTemplate
    )
    // handler CB is called when user pressed the section title
    row.handler = { [weak self] selectedRow, completion in
      guard let self else { completion(); return }
      if !isDetailTemplate {
        Task { @MainActor in
          let detailSectionRow = createHomeRow(section: section, isDetailTemplate: true)
          let detailListTemplate = CPListTemplate(title: section.headerTitle, sections: [
            CPListSection(items: detailSectionRow != nil ? [detailSectionRow!] : []),
          ])
          let _ = try? await interfaceController?
            .pushTemplate(detailListTemplate, animated: true)
          completion()
        }
      } else if isRandomSection {
        Task { @MainActor in
          switch section {
          case .randomAlbums:
            await sharedHome.updateRandomAlbums(isOfflineMode: isOfflineMode)
          case .compilations:
            await sharedHome.updateCompilations(isOfflineMode: isOfflineMode)
          case .randomArtists:
            await sharedHome.updateRandomArtists(isOfflineMode: isOfflineMode)
          case .favoriteAlbums:
            await sharedHome.updateFavoriteAlbums(isOfflineMode: isOfflineMode)
          case .favoriteArtists:
            await sharedHome.updateFavoriteArtists(isOfflineMode: isOfflineMode)
          case .randomGenres:
            await sharedHome.updateRandomGenres()
          case .randomSongs:
            await sharedHome.updateRandomSongs(isOfflineMode: isOfflineMode)
          case .lastTimePlayedPlaylists, .latestReleasedAlbums,
               .newestAlbums, .newestPodcastEpisodes, .podcasts,
               .radios, .recentlyPlayedAlbums:
            // do nothing
            break
          default:
            // fixed decade and genre sections have no refresh
            break
          }
          if section.isRandomSection {
            row.elements = createHomeRowImageElements(section: section, isDetail: true)
          }
          completion()
        }
      } else {
        completion()
      }
    }
    // listImageRowHandler CB is called when user pressed on a image inside the row
    row.listImageRowHandler = { [weak self] item, index, completion in
      guard let self,
            let selectedPlayable = sharedHome.data[section]?[index].playableContainable
      else { completion(); return }
      Task { @MainActor in
        if !isOfflineMode {
          do {
            try await selectedPlayable.fetch(
              storage: self.appDelegate.storage,
              librarySyncer: self.appDelegate.getMeta(activeAccountInfo).librarySyncer,
              playableDownloadManager: self.appDelegate.getMeta(activeAccountInfo)
                .playableDownloadManager
            )
          } catch {
            // ignore online fetch in CarPlay
          }
        }
        if let album = selectedPlayable as? Album {
          let albumTemplate = createAlbumSongListTemplate(for: album, onlyCached: isOfflineMode)
          let _ = try? await interfaceController?.pushTemplate(albumTemplate, animated: true)
          completion()
        } else if let playlist = selectedPlayable as? Playlist {
          let playlistDetailTemplate = CPListTemplate(title: playlist.name, sections: [
            CPListSection(items: [CPListTemplateItem]()),
          ])
          playlistDetailSection = playlistDetailTemplate
          createPlaylistDetailFetchController(playlist: playlist)
          interfaceController?.pushTemplate(playlistDetailTemplate, animated: true, completion: nil)
          completion()
        } else {
          self.appDelegate.player.play(context: PlayContext(containable: selectedPlayable))
          displayNowPlaying {
            completion()
          }
        }
      }
    }
    return row
  }

  func createHomeRowImageElements(
    section: HomeSection,
    isDetail: Bool
  )
    -> [CPListImageRowItemRowElement] {
    guard let sharedHome else { return [] }

    let alreadyCreatedData = homeRowData[section]
    let requestedData = sharedHome.data[section]
    if !isDetail,
       alreadyCreatedData ==
       requestedData {
      return homeImageRows[section]?.elements as? [CPListImageRowItemRowElement] ?? []
    }
    if !isDetail {
      homeRowData[section] = requestedData
    }
    // drop the targets of the elements which are replaced now
    for artworkID in Array(homeArtworkUpdate.keys) {
      homeArtworkUpdate[artworkID]?.removeAll { $0.section == section && $0.isDetail == isDetail }
      if homeArtworkUpdate[artworkID]?.isEmpty == true {
        homeArtworkUpdate[artworkID] = nil
      }
    }

    var imageRowElements = [CPListImageRowItemRowElement]()
    let items = requestedData ?? []
    for item in items {
      let containable = item.playableContainable
      let element = CPListImageRowItemRowElement(
        image: getImage(for: containable),
        title: containable.name,
        subtitle: containable.subtitle
      )
      for artwork in containable.getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
        .artworks {
        // trigger download only once
        if homeArtworkUpdate[artwork.uniqueID] == nil, let accountInfo = artwork.account?.info {
          appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
        }
        homeArtworkUpdate[artwork.uniqueID, default: []].append(HomeArtworkTarget(
          section: section,
          item: item,
          isDetail: isDetail,
          element: element
        ))
      }
      imageRowElements.append(element)
    }
    return imageRowElements
  }
}
