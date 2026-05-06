<tmpl_if detail_is_geo><a id="geo_filmsections" /></tmpl_if><tmpl_if detail_is_subject><a id="subject_filmsections" /></tmpl_if><tmpl_if detail_is_ware><a id="ware_filmsections" /></tmpl_if>

<tmpl_if is_de>
### Abschnitte von digitalisierten Mikrofilmen

Die Erschließung der digitalisierten Mikrofilme ist work in progress. Sie wird, Film für Film, von Mitgliedern des [Wikipedia Projekt Pressearchiv](https://de.wikipedia.org/wiki/Wikipedia:Projekt_Pressearchiv) in Zusammenarbeit mit der ZBW geleistet. Einige Filme sind vollständig erschlossen, einige nur auf oberster Ebene, andere gar nicht.<tmpl_if filming_loop> Die folgende Liste von Filmabschnitten ist daher unvollständig.</tmpl_if>

<tmpl_if is_secondary_category>Weiteres Material zum Thema ist möglicherweise verstreut über die <tmpl_var detail_title> Filmlisten, die primär <tmpl_var ordered_by> geordnet sind. ([1. Verfilmung](<tmpl_var filmlist1>), [2. Verfilmung](<tmpl_var filmlist2>)).</tmpl_if>

<tmpl_if filming_loop>[_Ausgegraute Abschnittsnamen_]{.gray} zeigen lediglich einen zufälligen Einschnitt, den Beginn eines neuen Films, an. Das entsprechende Thema kann bereits auf dem vorigen Film begonnen haben, und die angezeigte Anzahl Aufnahmen umfasst meist nicht nur das genannte Thema.</tmpl_if>
</tmpl_if>

<tmpl_if is_en>
### Sections of digitized microfilms

The indexing of the unprocessed digitized microfilms is work in progress. It is conducted, film by film, by members of the [Wikipedia Projekt Pressearchiv](https://de.wikipedia.org/wiki/Wikipedia:Projekt_Pressearchiv) in cooperation with ZBW. Some films are fully indexed, some only top-level, some not at all.<tmpl_if filming_loop> The list of film sections below is therefore incomplete.</tmpl_if>

<tmpl_if is_secondary_category>Further material about the topic may be dispersed across the <tmpl_var detail_title> film lists, which are primarily ordered <tmpl_var ordered_by> ([1st filming](<tmpl_var filmlist1>), [2nd filming](<tmpl_var filmlist2>)).</tmpl_if>

<tmpl_if filming_loop>[_Grayed-out section labels_]{.gray} indicate just an arbitrary cut at the beginning of an new film. The topic may have already started on the previous film, and the number of images may comprise much more than the given topic.</tmpl_if>
</tmpl_if>

<tmpl_loop filming_loop>
#### <tmpl_var detail_title> - <tmpl_var filming_title>

<p><tmpl_var legal></p>

<tmpl_if total_number_of_images>
<tmpl_if is_de>
<p>Gesamtzahl der Mikrofilmaufnahmen: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unbekannt - derzeit ggf. auffindbar nur über die [Filmliste](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_de>
<tmpl_if is_en>
<p>Total number of images: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unknown - currently only findable via the [film list](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_en>
</tmpl_if total_number_of_images>

<tmpl_if filmsection_loop>

::: {.sectiontable}

 | 
--|-------
<tmpl_loop filmsection_loop><a class="btn" href="<tmpl_var filmviewer_url>" rel="nofollow"><tmpl_var section_id></a> | <tmpl_if is_filmstartonly>_[</tmpl_if><tmpl_if section_label><tmpl_var section_label></tmpl_if> &#160; <tmpl_if image_count>[(<tmpl_var image_count> <tmpl_if is_de>Aufnahmen</tmpl_if><tmpl_if is_en>images</tmpl_if>)]{.hint}</tmpl_if><tmpl_if is_filmstartonly>]{.gray}_</tmpl_if>
</tmpl_loop filmsection_loop>

:::

</tmpl_if filmsection_loop>

</tmpl_loop filming_loop>

