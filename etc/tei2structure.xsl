<xsl:stylesheet xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:tei="http://www.tei-c.org/ns/1.0"
                xmlns:exsl="http://exslt.org/common"
                xmlns:glam="urn:umich:lib:dor:model:2026:resource:glam"
                xmlns:mets="http://www.loc.gov/METS/v2"
                exclude-result-prefixes="xs exsl glam tei"
                version="1.0">

  <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

  <xsl:param name="idno" />
  <xsl:param name="encodingtype" />

  <xsl:variable name="badchars" select="':'"/>
  <xsl:variable name="goodchars" select="'-'"/>


  <xsl:template match="/">
    <xsl:variable name="n" select="//tei:editorialdecl/@n" />
    <mets:structMap>
      <mets:div TYPE="{$encodingtype}">
        <xsl:choose>
          <xsl:when test="$n = '1'">
            <xsl:apply-templates select="//tei:pb" />
          </xsl:when>
          <xsl:when test="$n = '2'">
            <xsl:apply-templates select="//tei:div1[@glam:node]" />
          </xsl:when>
          <xsl:otherwise />
        </xsl:choose>
      </mets:div>
    </mets:structMap>
  </xsl:template>

  <xsl:template match="tei:div1[@glam:node]">
    <mets:div TYPE="section" ORDER="{position()}" MDID="{@glam:node}~md.service.json">
      <xsl:apply-templates select="tei:pb" />
    </mets:div>
  </xsl:template>

  <xsl:template match="tei:pb">
    <mets:div TYPE="page" ORDER="{@glam:seq}">
      <xsl:if test="@n">
        <xsl:attribute name="ORDERLABEL"><xsl:value-of select="@n" /></xsl:attribute>
      </xsl:if>
      <mets:div TYPE="canvas">
        <mets:mptr LOCTYPE="URL" LOCREF="{$idno}/{@facs}" />
      </mets:div>
    </mets:div>
  </xsl:template>
</xsl:stylesheet>