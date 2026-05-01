<xsl:stylesheet xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:tei="http://www.tei-c.org/ns/1.0"
                xmlns:exsl="http://exslt.org/common"
                xmlns:glam="urn:umich:lib:dor:model:2026:resource:glam"
                xmlns:mets="http://www.loc.gov/METS/v2"
                extension-element-prefixes="glam"
                exclude-result-prefixes="xs exsl glam tei"
                version="1.0">

  <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

  <xsl:param name="local_identifier" />
  <xsl:variable name="mdid-folio-source" select="glam:hash_id(concat($local_identifier, '#source'))" />
  <xsl:variable name="istruct_n" select="count(//Record[@name='entry']//Field[starts-with(@abbrev, 'istruct_')])" />

  <xsl:template match="/">
    <mets:structMap>
      <mets:div TYPE="folio">
        <xsl:choose>
          <xsl:when test="//RelatedViews[View]">
            <xsl:apply-templates select="//RelatedViews" />
          </xsl:when>
          <xsl:when test="//RelatedViewsMenu/Option">
            <xsl:apply-templates select="//RelatedViewsMenu/Option" />
          </xsl:when>
          <xsl:otherwise>
            <xsl:apply-templates select="//MediaInfo" />
          </xsl:otherwise>
        </xsl:choose>        
      </mets:div>
    </mets:structMap>
  </xsl:template>

  <xsl:template match="MediaInfo">
    <xsl:variable name="m_fn" select="glam:basename(string(m_fn))" />
    <xsl:variable name="mdid-source" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#source'))" />
    <xsl:variable name="mdid-service" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#service'))" />
    <mets:div TYPE="sheet" ORDER="1">
      <xsl:attribute name="MDID">
        <xsl:value-of select="$mdid-folio-source" />
        <xsl:text> </xsl:text>
        <xsl:if test="//SlideMetadata/slide[@m_fn = $m_fn]">
          <xsl:value-of select="$mdid-source" />
          <xsl:text> </xsl:text>
        </xsl:if>
        <xsl:value-of select="$mdid-service" />
      </xsl:attribute>
      <mets:div TYPE="canvas">
        <mets:mptr LOCTYPE="URL" LOCREF="{$local_identifier}/{$m_fn}" />
      </mets:div>
    </mets:div>
  </xsl:template>

  <xsl:template match="RelatedViewsMenu/Option">
    <xsl:variable name="m_fn" select="glam:basename(string(Value))" />
    <xsl:variable name="mdid-source" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#source'))" />
    <xsl:variable name="mdid-service" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#service'))" />
    <mets:div TYPE="sheet" ORDER="{position()}">
      <xsl:attribute name="MDID">
        <xsl:value-of select="$mdid-folio-source" />
        <xsl:text> </xsl:text>
        <xsl:if test="//SlideMetadata/slide[@m_fn = $m_fn]">
          <xsl:value-of select="$mdid-source" />
          <xsl:text> </xsl:text>
        </xsl:if>
        <xsl:value-of select="$mdid-service" />
      </xsl:attribute>
      <mets:div TYPE="canvas">
        <mets:mptr LOCTYPE="URL" LOCREF="{$local_identifier}/{$m_fn}" />
      </mets:div>
    </mets:div>
  </xsl:template>

  <xsl:template match="RelatedViews">
    <xsl:apply-templates select="View" />
  </xsl:template>

  <xsl:template match="View">
    <mets:div LABEL="{Name}" TYPE="view" ORDER="{position()}">
      <xsl:apply-templates select="Row" />
    </mets:div>
  </xsl:template>

  <xsl:template match="Row">
    <mets:div TYPE="row" ORDER="{@y}">
      <xsl:apply-templates select="Column" />
    </mets:div>
  </xsl:template>

  <xsl:template match="Column">
    <mets:div TYPE="column" ORDER="{@x}">
      <mets:div TYPE="sheet">
        <xsl:variable name="m_fn" select="glam:from_cgi(string(Url[@name='EntryLink']))" />
        <xsl:variable name="mdid-source" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#source'))" />
        <xsl:variable name="mdid-service" select="glam:hash_id(concat($local_identifier, '.', $m_fn, '#service'))" />
        <xsl:attribute name="MDID">
          <xsl:value-of select="$mdid-folio-source" />
          <xsl:text> </xsl:text>
          <xsl:if test="//SlideMetadata/slide[@m_fn = $m_fn]">
            <xsl:value-of select="$mdid-source" />
            <xsl:text> </xsl:text>
          </xsl:if>
          <xsl:value-of select="$mdid-service" />
        </xsl:attribute>
        <xsl:attribute name="debug-fn">
          <xsl:value-of select="$m_fn" />
        </xsl:attribute>
        <mets:div TYPE="canvas">
          <mets:mptr LOCTYPE="URL" LOCREF="{$local_identifier}/{$m_fn}" />
        </mets:div>
      </mets:div>
    </mets:div>
  </xsl:template>

</xsl:stylesheet>