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

  <xsl:param name="idno" />
  <xsl:param name="encodingtype" />

  <xsl:variable name="badchars" select="':'"/>
  <xsl:variable name="goodchars" select="'-'"/>


  <xsl:template match="/">
    <xsl:variable name="n" select="//tei:editorialdecl/@n" />
    <mets:structMap>
      <xsl:choose>
        <xsl:when test="$n = '1'">
          <xsl:variable name="mdid-source" select="glam:hash_id(concat($idno, '#source'))" />
          <xsl:variable name="mdid-service" select="glam:hash_id(concat($idno, '#service'))" />
          <mets:div TYPE="{$encodingtype}" MDID="{$mdid-service}">
            <xsl:apply-templates select="//tei:pb" />
          </mets:div>
        </xsl:when>
        <xsl:when test="$n = '2'">
          <mets:div TYPE="{$encodingtype}" MDID="{glam:hash_id(concat($idno, '#service'))}">
            <xsl:apply-templates select="//tei:div1[@glam:node]">
              <xsl:with-param name="n" select="$n" />
            </xsl:apply-templates>
          </mets:div>
        </xsl:when>
        <xsl:when test="$n = '4'">
          <mets:div TYPE="{$encodingtype}" MDID="{glam:hash_id(concat($idno, '#service'))}">
            <xsl:apply-templates select="//tei:div1[@glam:node]">
              <xsl:with-param name="n" select="$n" />
            </xsl:apply-templates>
          </mets:div>
        </xsl:when>
        <xsl:otherwise />
      </xsl:choose>
    </mets:structMap>
  </xsl:template>

  <xsl:template match="tei:div1[@glam:node]" priority="101">
    <xsl:param name="n" select="'1'" />
    <xsl:variable name="mdid-source" select="glam:hash_id(concat(@glam:node, '#source'))" />
    <xsl:variable name="mdid-service" select="glam:hash_id(concat(@glam:node, '#service'))" />
    <xsl:variable name="type">
      <xsl:choose>
        <xsl:when test="@type">
          <xsl:value-of select="@type" />
        </xsl:when>
        <xsl:otherwise>section</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <mets:div 
      TYPE="{$type}" 
      ORDER="{position()}" 
      MDID="{$mdid-service}"
      >
      <xsl:choose>
        <xsl:when test="$n = '4'">
          <xsl:variable name="end-node" select="following-sibling::tei:div1[@glam:node][1]/@glam:node" />
          <mets:fptr>
            <mets:area FILEID="{$idno}/{$idno}.tei.xml" BEGIN="{@xml:id}">
              <xsl:if test="normalize-space($end-node)">
                <xsl:attribute name="END">
                  <xsl:value-of select="glam:hash_id(concat($end-node, '#source'))" />
                </xsl:attribute>
              </xsl:if>
            </mets:area>
          </mets:fptr>
          <xsl:apply-templates select="node()[@glam:node]">
            <xsl:with-param name="n" select="$n" />
          </xsl:apply-templates>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="tei:pb" />
        </xsl:otherwise>
      </xsl:choose>
      <!-- <xsl:apply-templates select="tei:pb" /> -->
    </mets:div>
  </xsl:template>

  <xsl:template match="node()[@glam:node]">
    <xsl:param name="n" />
    <xsl:variable name="mdid-source" select="glam:hash_id(concat(@glam:node, '#source'))" />
    <xsl:variable name="mdid-service" select="glam:hash_id(concat(@glam:node, '#service'))" />
    <xsl:variable name="type">
      <xsl:choose>
        <xsl:when test="@type">
          <xsl:value-of select="@type" />
        </xsl:when>
        <xsl:otherwise>section</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <mets:div 
      TYPE="{$type}" 
      ORDER="{position()}" 
      MDID="{$mdid-service}">
      <xsl:if test="$n = '4'">
        <xsl:variable name="end-node" select="following-sibling::node()[@glam:node][1][@glam:node]" />
        <mets:fptr>
          <mets:area FILEID="{$idno}/{$idno}.tei.xml" BEGIN="{@xml:id}">
            <xsl:if test="normalize-space($end-node/@glam:node)">
              <xsl:attribute name="END">
                <xsl:value-of select="$end-node/@xml:id" />
              </xsl:attribute>
            </xsl:if>
          </mets:area>
        </mets:fptr>
      </xsl:if>
      <xsl:apply-templates select="node()[@glam:node]">
        <xsl:with-param name="n" select="$n" />
      </xsl:apply-templates>
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