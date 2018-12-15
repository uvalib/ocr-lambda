package main

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/julienschmidt/httprouter"
)

type pageInfo struct {
	PID      string
	Filename string
	Title    string
	txtFile  string
	lang     string
}

type ocrRequest struct {
	pid   string
	unit  string
	pages string
	token string
	email string
}

type ocrInfo struct {
	req     ocrRequest
	unitID  int
	workDir string
	destDir string
	pages   []pageInfo
}

/**
 * Handle a request for OCR of page images
 */
func generateHandler(w http.ResponseWriter, r *http.Request, params httprouter.Params) {
	logger.Printf("%s %s", r.Method, r.RequestURI)

	ocr := ocrInfo{}

	// save fields from original request
	ocr.req.pid = params.ByName("pid")
	ocr.req.unit = r.URL.Query().Get("unit")
	ocr.req.email = r.URL.Query().Get("email")
	ocr.req.pages = r.URL.Query().Get("pages")
	ocr.req.token = r.URL.Query().Get("token")

	// save info generated from the original request
	ocr.unitID, _ = strconv.Atoi(ocr.req.unit)
	ocr.workDir = ocr.req.pid

	if ocr.unitID > 0 {
		// if pages from a specific unit are requested, put them
		// in a unit subdirectory under the metadata pid
		ocr.workDir = fmt.Sprintf("%s/%d", ocr.req.pid, ocr.unitID)
	}

	if len(ocr.req.pages) > 0 {
		if len(ocr.req.token) == 0 {
			logger.Printf("Request for partial OCR is missing a token")
			w.WriteHeader(http.StatusBadRequest)
			fmt.Fprintf(w, "Missing token")
			return
		}
		ocr.workDir = ocr.req.token
		logger.Printf("Request for partial OCR including pages: %s", ocr.req.pages)
	}

	// See if destination already extsts...
	ocr.destDir = fmt.Sprintf("%s/%s", config.storageDir.value, ocr.workDir)

	if _, err := os.Stat(ocr.destDir); err == nil {
		// path already exists; don't start another request, just start
		// normal completion polling routine
		logger.Printf("Request already in progress or completed")
		monitorProgressAndNotifyResults(ocr.workDir, ocr.req.pid, ocr.req.email)
		return
	}

	tsPages, tsErr := tsGetPages(ocr, w)

	if tsErr != nil {
		logger.Printf("Tracksys API error: [%s]", tsErr.Error())
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprintf(w, "Tracksys API error: [%s]", tsErr.Error())
		return
	}

	for _, p := range tsPages {
		if p.PID == "" {
			logger.Printf("skipping page with missing pid: %V", p)
			continue
		}

		ocr.pages = append(ocr.pages, p)
	}

	if len(ocr.pages) == 0 {
		logger.Printf("No pages found")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprintf(w, "No pages found for this PID")
		return
	}

	var s []string
	for _, p := range ocr.pages {
		s = append(s, p.PID)
	}
	logger.Printf("%d pids: [%s]", len(s), strings.Join(s, " "))

	txt, txtErr := tsGetText(ocr.req.pid)
	if txtErr != nil {
		logger.Printf("tsGetText() error: [%s]", txtErr.Error())
	} else {
		logger.Printf("text:\n\n%s\n\n", txt)
		//tsPostText(ocr.req.pid, "blah")
	}

	// kick off lengthy OCR generation in a go routine
	go generateOcr(ocr)
}

func generateOcr(ocr ocrInfo) {
	logger.Printf("would call awsGenerateOcr()...")
	//	awsGenerateOcr(ocr)
}
